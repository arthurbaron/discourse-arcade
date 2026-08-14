# frozen_string_literal: true

# Everything the admin stats page shows, in one place.
#
# No new data is collected for any of this. A score row has always carried who
# played, which game, when, and how long the run took, so this class is only a
# different set of questions asked of rows that were already there.
#
# A "play" is an accepted score. A run that was started and never finished has no
# score row, so it is not counted here: that is a separate question (how often a
# game is abandoned) and deliberately not in this first version.
#
# Two decisions worth knowing about, because they change the numbers:
#
#   Days are bucketed in the viewer's own timezone, not the server's. "How busy
#   was Saturday" is a question about the reader's Saturday, and Discourse
#   already knows each user's zone from their browser. Falling back to UTC is
#   only for a user who has never had one recorded.
#
#   Durations are reported as a median, not a mean. A run is timed from handing
#   out the token to receiving the score, so a tab left open over lunch is a
#   legitimate row with a wildly untypical duration. One of those drags a mean
#   for good; a median shrugs it off.
class ArcadeStats
  RECENT_DAYS = 7
  TREND_DAYS = 14
  TROPHY_LEADERS = 5

  def self.call(viewer: nil)
    new(viewer: viewer).call
  end

  def initialize(viewer: nil)
    @zone = resolve_zone(viewer)
  end

  def call
    {
      timezone: @zone.name,
      totals: totals,
      games: games,
      trophies: trophies,
      by_day: by_day,
      by_weekday: by_weekday,
    }
  end

  private

  def resolve_zone(viewer)
    name = viewer&.user_option&.timezone.presence
    (name && ActiveSupport::TimeZone[name]) || Time.zone || ActiveSupport::TimeZone["UTC"]
  end

  def accepted
    ArcadeScore.accepted
  end

  # Midnight, this many days ago, in the viewer's zone. Day 0 is today, so a
  # 7 day window is today plus the six before it.
  def start_of_day_ago(days)
    @zone.now.beginning_of_day - days.days
  end

  def totals
    today = accepted.where(created_at: start_of_day_ago(0)..)
    week = accepted.where(created_at: start_of_day_ago(RECENT_DAYS - 1)..)

    {
      plays_today: today.count,
      plays_week: week.count,
      plays_total: accepted.count,
      # Distinct people, not plays. A hundred plays by three regulars and a
      # hundred by forty members are both "popular" and look identical on a
      # play count alone, which is the whole reason this column exists.
      players_week: week.distinct.count(:user_id),
      players_total: accepted.distinct.count(:user_id),
    }
  end

  def games
    since = start_of_day_ago(RECENT_DAYS - 1)

    recent_counts = accepted.where(created_at: since..).group(:arcade_game_id).count
    total_counts = accepted.group(:arcade_game_id).count
    player_counts = accepted.group(:arcade_game_id).distinct.count(:user_id)
    last_played = accepted.group(:arcade_game_id).maximum(:created_at)
    medians = median_durations
    bests = best_scores

    # Every game, including ones switched off and ones never played, so a zero
    # is visible as a zero rather than as an absent row.
    ArcadeGame
      .order(position: :asc, name: :asc)
      .map do |game|
        {
          slug: game.slug,
          name: game.name,
          enabled: game.enabled,
          plays_week: recent_counts[game.id] || 0,
          plays_total: total_counts[game.id] || 0,
          players_total: player_counts[game.id] || 0,
          median_seconds: medians[game.id],
          last_played_at: last_played[game.id],
          best_score: bests[game.id],
          score_unit: game.score_unit,
        }
      end
  end

  # Postgres can do this in one pass, and doing it in Ruby would mean loading
  # every duration to throw almost all of them away.
  def median_durations
    rows =
      accepted
        .group(:arcade_game_id)
        .pluck(
          :arcade_game_id,
          Arel.sql("PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_seconds)"),
        )

    rows.to_h { |game_id, median| [game_id, median&.round] }
  end

  # The single best accepted score per game, respecting each game's direction:
  # Recall and the time trials are won with a low number, not a high one.
  def best_scores
    directions = ArcadeGame.pluck(:id, :score_direction).to_h

    highs, lows = directions.keys.partition { |id| directions[id] == "high" }

    best = {}
    best.merge!(accepted.where(arcade_game_id: highs).group(:arcade_game_id).maximum(:score))
    best.merge!(accepted.where(arcade_game_id: lows).group(:arcade_game_id).minimum(:score))
    best
  end

  # Deliberately the same source as the trophy next to a poster's name, so the
  # two can never disagree about who holds what.
  def trophies
    holders = ArcadeRecordHolders.map
    return [] if holders.blank?

    top =
      holders
        .sort_by { |user_id, names| [-names.length, user_id] }
        .first(TROPHY_LEADERS)

    users = User.where(id: top.map(&:first)).index_by(&:id)

    top.filter_map do |user_id, names|
      user = users[user_id]
      next if user.nil?

      {
        username: user.username,
        avatar_url: user.avatar_template_url.gsub("{size}", "48"),
        count: names.length,
        games: names.sort,
      }
    end
  end

  # Bucketed in Ruby rather than SQL, because the boundaries have to land in the
  # viewer's zone and this is a forum arcade: the row count is small enough that
  # clarity is worth more than the query.
  def by_day
    first_day = start_of_day_ago(TREND_DAYS - 1)
    stamps = accepted.where(created_at: first_day..).pluck(:created_at)

    counts = stamps.group_by { |at| at.in_time_zone(@zone).to_date }.transform_values(&:size)

    (0...TREND_DAYS).map do |offset|
      date = (first_day + offset.days).to_date
      { date: date.iso8601, count: counts[date] || 0 }
    end
  end

  # All time, because the question is which day of the week people play on and
  # a fortnight of data cannot answer that.
  def by_weekday
    stamps = accepted.pluck(:created_at)
    counts = stamps.group_by { |at| at.in_time_zone(@zone).wday }.transform_values(&:size)

    # Monday first, the way a European week reads.
    [1, 2, 3, 4, 5, 6, 0].map do |wday|
      { wday: wday, name: Date::DAYNAMES[wday], count: counts[wday] || 0 }
    end
  end
end
