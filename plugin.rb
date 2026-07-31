# frozen_string_literal: true

# name: discourse-arcade
# about: Arcade of self-hosted HTML5 games with per-game leaderboards
# version: 0.1.0
# authors: Online Arsenal Community
# url: https://github.com/arthurbaron/discourse-arcade

enabled_site_setting :arcade_enabled

register_asset "stylesheets/arcade.css"

# The trophy belongs to Bookie, so the arcade gets its own mark.
register_svg_icon "gamepad"
register_svg_icon "star"

after_initialize do
  [
    "app/models/arcade_game",
    "app/models/arcade_run",
    "app/models/arcade_score",
    "app/services/arcade_score_submission",
    "app/controllers/arcade_page_controller",
    "app/controllers/arcade_controller",
  ].each { |f| require_relative f }

  # Prepend so these win before Discourse's catch-all route.
  Discourse::Application.routes.prepend do
    # Ember app shell. Both paths boot the same SPA.
    get "/arcade" => "arcade_page#index"
    get "/arcade/g/:slug" => "arcade_page#index"

    # JSON API. Namespaced under /api so it can never collide with a game slug.
    get "/arcade/api/games" => "arcade#index"
    get "/arcade/api/games/:slug" => "arcade#show"
    post "/arcade/api/games/:slug/runs" => "arcade#start_run"
    post "/arcade/api/runs/:token" => "arcade#submit_score"
    delete "/arcade/api/scores/:id" => "arcade#destroy_score"
  end
end
