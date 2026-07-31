# frozen_string_literal: true

# A run is handed out by the server when a player starts a game, and can be
# redeemed for exactly one score. No token, no score.
class ArcadeRun < ActiveRecord::Base
  belongs_to :user
  belongs_to :arcade_game

  def self.issue!(user, game)
    create!(user_id: user.id, arcade_game_id: game.id, token: SecureRandom.hex(16))
  end

  def self.ttl
    SiteSetting.arcade_run_token_ttl_minutes.to_i.minutes
  end

  def consumed?
    consumed_at.present?
  end

  def expired?
    created_at < self.class.ttl.ago
  end

  def elapsed_seconds
    (Time.zone.now - created_at).to_i
  end

  def consume!
    update!(consumed_at: Time.zone.now)
  end
end
