# frozen_string_literal: true

# Who holds the all-time record on each game.
#
# The trophy next to a poster's name stays with the all-time records, even though
# the boards themselves now run per month. It was moved to the monthly leaders
# for a day and moved back on purpose: the monthly race has its own home on the
# boards and the season page, and the trophy is the one thing that still marks a
# record nobody has beaten.
#
# The point of this class is that the answer is tiny and global: with a handful
# of games, at most a handful of people hold anything at all, forum wide. So it
# is built once, cached, and every post that needs it does a hash lookup rather
# than a query of its own. That is what keeps a badge next to a username from
# turning a twenty post topic into twenty extra queries.
class ArcadeRecordHolders
  CACHE_KEY = "arcade_record_holders"

  # A backstop only. Real changes clear the cache explicitly, so this is just
  # insurance against a missed invalidation somewhere.
  CACHE_TTL = 15.minutes

  # { user_id => ["2048", "Penalty"] }
  def self.map
    Discourse.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { build }
  end

  def self.build
    holders = {}

    ArcadeGame.listed.each do |game|
      # within: nil is the all-time board. Without it this would follow the
      # leaderboard's default, which is the current month.
      leader = game.leaderboard(limit: 1, within: nil).first
      next if leader.nil?

      holders[leader.user_id] ||= []
      holders[leader.user_id] << game.name
    end

    holders
  end

  def self.clear!
    Discourse.cache.delete(CACHE_KEY)
    # Every path that adds or pulls a score comes through here, and any of them
    # can move a monthly placing, so the season table goes too.
    ArcadeSeason.clear!
  end

  def self.for_user(user_id)
    return [] if user_id.blank?
    map[user_id] || []
  end
end
