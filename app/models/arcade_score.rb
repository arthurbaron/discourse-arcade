# frozen_string_literal: true

class ArcadeScore < ActiveRecord::Base
  belongs_to :user
  belongs_to :arcade_game
  belongs_to :arcade_run

  scope :accepted, -> { where(rejected: false) }

  def reject!(reason:, moderator:)
    update!(rejected: true, rejected_reason: reason, rejected_by_id: moderator&.id)
  end
end
