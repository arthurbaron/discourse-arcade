# frozen_string_literal: true

# Turning a game on and off from admin. The column and the filtering were already
# there, so this is only the door to them: ArcadeGame.listed drops anything
# disabled, which takes the game off /arcade and out of ArcadeRecordHolders, and
# the after_commit on the model clears the flair cache by itself.
#
# Deliberately not a destructive screen. Disabling keeps every score, so a game
# switched back on comes back with its leaderboard intact.
class AdminArcadeController < Admin::AdminController
  def index
    render json: { games: ArcadeGame.order(position: :asc).map { |g| serialize_game(g) } }
  end

  def update
    game = ArcadeGame.find(params[:id])
    game.update!(enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))

    render json: { game: serialize_game(game) }
  end

  private

  def serialize_game(game)
    {
      id: game.id,
      slug: game.slug,
      name: game.name,
      tagline: game.tagline,
      thumbnail_url: game.thumbnail_url,
      enabled: game.enabled,
      scores_count: game.arcade_scores.accepted.count,
    }
  end
end
