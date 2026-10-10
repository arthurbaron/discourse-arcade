# frozen_string_literal: true

# The season table: who did best across every game, month after month.
#
# It cannot add up raw points. The games score on wildly different scales, so a
# single middling Intercept run (six figures) outweighs everything anyone could
# ever score in Penalty, Darts and Snake together, and the "season" would just be
# the Intercept board. So it scores placings, the way a racing championship
# does: every game, every month, the top five earn POINTS. That rewards playing
# widely and coming back every month, and it has a property worth keeping: a
# rule change halfway through a season distorts nothing, because each month is
# judged entirely inside its own rules.
#
# A game only pays out in a month where at least MIN_PLAYERS took part. A podium
# needs three people; without that, the one person who opened a quiet game once
# would walk off with ten points for showing up.
#
# Points earned stay earned. Every game counts, switched on or not, so turning a
# game off later never takes points away from anyone.
class ArcadeSeason
  POINTS = [10, 7, 5, 3, 1].freeze
  MIN_PLAYERS = 3

  # Each finished month keeps its own top five on the season page, five because
  # five is how far the points go in every game. Without it a month's result was
  # all but invisible once the board reset: the "last month" line only shows on
  # an empty board, so it vanished with the first run of the new month, and
  # whoever won September had nowhere it still said so.
  MONTH_TOP = 5

  CACHE_TTL = 15.minutes

  def self.standings(season = ArcadePeriod.current_season)
    Discourse.cache.fetch(cache_key(season), expires_in: CACHE_TTL) do
      new(season).standings
    end
  end

  # Called from ArcadeRecordHolders.clear!, which every path that adds or pulls
  # a score already goes through, so the two caches can never drift apart.
  def self.clear!
    Discourse.cache.delete(cache_key(ArcadePeriod.current_season))
  end

  # Bump whenever the shape of the table changes. Found the hard way in
  # development: a table cached by the previous code had no per-month list, and
  # the new controller crashed on it until the entry happened to expire. A
  # versioned key means new code never reads an entry old code wrote.
  CACHE_VERSION = 2

  # Carries the current month as well, so a month rolling over is a new entry
  # rather than fifteen minutes of last month's "in progress" label.
  def self.cache_key(season)
    "arcade_season:v#{CACHE_VERSION}:#{season}:#{ArcadePeriod.key(ArcadePeriod.current_month)}"
  end

  def initialize(season)
    @season = season
    @months = ArcadePeriod.months_of(season)
  end

  def standings
    totals = empty_tally
    by_month = Hash.new { |hash, month| hash[month] = empty_tally }
    counted = Hash.new(0)

    qualifying_pairs.each do |game, month|
      counted[month] += 1

      game
        .leaderboard(limit: POINTS.length, within: ArcadePeriod.range(month))
        .each_with_index do |entry, place|
          # The same placing counts twice: once towards the season, once towards
          # its own month, so a month's top five is scored exactly like the season.
          [totals, by_month[month]].each do |tally|
            row = tally[entry.user_id]
            row[:points] += POINTS[place]
            row[:wins] += 1 if place == 0
            row[:podiums] += 1 if place < 3
          end
        end
    end

    # Everyone in any month is also in the season totals, so one lookup covers
    # the season table and every month.
    users = User.where(id: totals.keys).index_by(&:id)

    {
      season: @season,
      label: ArcadePeriod.season_label(@season),
      months:
        @months.map do |month|
          current = month == ArcadePeriod.current_month
          {
            key: ArcadePeriod.key(month),
            label: ArcadePeriod.label(month),
            current: current,
            games_counted: counted[month],
            # Only finished months get one. The month in progress is already the
            # live table, and a result that can still change is not a result.
            # Ties on the last place are kept, so a shared fifth shows both.
            top:
              (
                if current
                  []
                else
                  ranked(by_month[month], users).select { |row| row[:rank] <= MONTH_TOP }
                end
              ),
          }
        end,
      rules: {
        points: POINTS,
        min_players: MIN_PLAYERS,
        month_top: MONTH_TOP,
      },
      standings: ranked(totals, users),
    }
  end

  private

  def empty_tally
    Hash.new { |hash, user_id| hash[user_id] = { points: 0, wins: 0, podiums: 0 } }
  end

  # Every (game, month) in the season where enough people played, found with one
  # grouped count rather than a leaderboard query per pair. Most pairs on a
  # forum this size never reach three players, so this is also what keeps the
  # number of leaderboard queries down to the ones that actually pay out.
  def qualifying_pairs
    return [] if @months.empty?

    month_sql = "date_trunc('month', created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{ArcadePeriod::ZONE}')"

    counts =
      ArcadeScore
        .accepted
        .where(created_at: ArcadePeriod.season_range(@season))
        .group(:arcade_game_id, Arel.sql(month_sql))
        .distinct
        .count(:user_id)

    games = ArcadeGame.where(id: counts.keys.map(&:first).uniq).index_by(&:id)

    counts
      .filter_map do |(game_id, month_start), players|
        next if players < MIN_PLAYERS
        game = games[game_id]
        next if game.nil?
        [game, month_start.to_date]
      end
      .sort_by { |game, month| [month, game.position, game.id] }
  end

  # Points first, then most month wins, then most podiums, so a tie on points
  # goes to whoever actually came first more often. Players level on all three
  # share a rank.
  def ranked(totals, users)
    rows =
      totals
        .filter_map do |user_id, row|
          user = users[user_id]
          next if user.nil?

          row.merge(
            user_id: user_id,
            username: user.username,
            avatar_url: user.avatar_template.gsub("{size}", "48"),
          )
        end
        .sort_by { |row| [-row[:points], -row[:wins], -row[:podiums], row[:username].downcase] }

    previous = nil
    rows.each_with_index do |row, index|
      tie = previous && previous.values_at(:points, :wins, :podiums) == row.values_at(:points, :wins, :podiums)
      row[:rank] = tie ? previous[:rank] : index + 1
      previous = row
    end

    rows
  end
end
