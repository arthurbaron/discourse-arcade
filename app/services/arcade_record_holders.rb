# frozen_string_literal: true

# Who currently holds first place on each game.
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
      leader = game.leaderboard(limit: 1).first
      next if leader.nil?

      holders[leader.user_id] ||= []
      holders[leader.user_id] << game.name
    end

    holders
  end

  def self.clear!
    Discourse.cache.delete(CACHE_KEY)
  end

  def self.for_user(user_id)
    return [] if user_id.blank?
    map[user_id] || []
  end
end
