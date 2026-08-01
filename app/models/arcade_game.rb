# frozen_string_literal: true

class ArcadeGame < ActiveRecord::Base
  has_many :arcade_scores, dependent: :destroy
  has_many :arcade_runs, dependent: :destroy

  DIRECTIONS = %w[high low].freeze

  validates :slug, presence: true, uniqueness: true
  validates :name, :entry_path, presence: true
  validates :score_direction, inclusion: { in: DIRECTIONS }

  scope :listed, -> { where(enabled: true).order(position: :asc, name: :asc) }

  # Enabling, disabling or renaming a game changes who holds what, and the
  # seed task goes through here too.
  after_commit { ArcadeRecordHolders.clear! }

  def higher_is_better?
    score_direction == "high"
  end

  # Games live in the plugin's public/ dir, which Discourse symlinks to
  # public/plugins/discourse-arcade at boot.
  def play_url
    "#{Discourse.base_path.presence}/plugins/discourse-arcade/games/#{entry_path}"
  end

  def thumbnail_url
    return nil if thumbnail.blank?
    "#{Discourse.base_path.presence}/plugins/discourse-arcade/images/thumbs/#{thumbnail}"
  end

  # Best score per user, ranked. One row per player, so a leaderboard never
  # fills up with the same person.
  def leaderboard(limit: 10)
    direction = higher_is_better? ? "DESC" : "ASC"

    best_per_user =
      ArcadeScore
        .select("DISTINCT ON (user_id) *")
        .where(arcade_game_id: id, rejected: false)
        .order(Arel.sql("user_id, score #{direction}, created_at ASC"))

    ArcadeScore
      .from(best_per_user, :arcade_scores)
      .includes(:user)
      .order(Arel.sql("score #{direction}, created_at ASC"))
      .limit(limit)
  end

  def personal_best_for(user_id)
    return nil if user_id.blank?

    arcade_scores
      .where(user_id: user_id, rejected: false)
      .order(score: higher_is_better? ? :desc : :asc, created_at: :asc)
      .first
  end

  # How many distinct players sit above this user on the board, plus one.
  # Ties are broken by who got there first, same as the leaderboard.
  def rank_for(user_id)
    best = personal_best_for(user_id)
    return nil if best.nil?

    beats_it =
      if higher_is_better?
        "score > :s OR (score = :s AND created_at < :t)"
      else
        "score < :s OR (score = :s AND created_at < :t)"
      end

    ahead =
      ArcadeScore
        .accepted
        .where(arcade_game_id: id)
        .where(beats_it, s: best.score, t: best.created_at)
        .distinct
        .count(:user_id)

    ahead + 1
  end

  def plays_count
    arcade_scores.where(rejected: false).count
  end
end
