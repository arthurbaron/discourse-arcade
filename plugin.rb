# frozen_string_literal: true

# name: discourse-arcade
# about: Arcade of self-hosted HTML5 games with per-game leaderboards
# version: 0.1.0
# authors: Online Arsenal Community
# url: https://github.com/arthurbaron/discourse-arcade

enabled_site_setting :arcade_enabled

register_asset "stylesheets/arcade.css"
# Admin pages load their own bundle, so admin styling has to say so.
register_asset "stylesheets/admin/arcade-admin.css", :admin

# A star marks a personal best, and the trophy is the record flair next to a
# poster's name.
register_svg_icon "star"
register_svg_icon "trophy"
# The admin stats link. Registering it is what puts it in the icon sprite at
# all; see the note on "gamepad" below for what happens when one is missing.
register_svg_icon "chart-bar"

# Keep this even though nothing in this plugin renders it. The heading moved to a
# real emoji, so it looked unused and got removed once, which silently emptied
# the gamepad out of the icon sprite and broke the sidebar link to /arcade that
# an admin had picked it for. Sidebar link icons are not one of the sources that
# fill the sprite, so registering it here is what keeps it selectable at all.
register_svg_icon "gamepad"

# Admin gets its own page under Plugins, with a tab for switching individual
# games on and off.
add_admin_route "arcade.admin.title", "discourse-arcade", use_new_show_route: true

after_initialize do
  [
    "app/models/arcade_game",
    "app/models/arcade_run",
    "app/models/arcade_score",
    "app/services/arcade_score_submission",
    "app/services/arcade_record_holders",
    "app/services/arcade_assets_version",
    "app/services/arcade_stats",
    "app/controllers/arcade_page_controller",
    "app/controllers/arcade_controller",
    "app/controllers/admin_arcade_controller",
  ].each { |f| require_relative f }

  # Records held, for the badge next to a poster's name.
  #
  # The condition runs before the attribute and memoises on the serializer
  # instance, so a post costs one cached lookup rather than two, and the field is
  # left out entirely for the vast majority of posts by people holding nothing.
  # respect_plugin_enabled is on by default, so a disabled arcade drops the field
  # without needing a check here.
  add_to_serializer(
    :post,
    :arcade_records,
    include_condition: -> do
      SiteSetting.arcade_show_record_flair &&
        (@arcade_records ||= ArcadeRecordHolders.for_user(object.user_id)).present?
    end,
  ) { @arcade_records ||= ArcadeRecordHolders.for_user(object.user_id) }

  # Prepend so these win before Discourse's catch-all route.
  Discourse::Application.routes.prepend do
    # Ember app shell. All of these boot the same SPA. /arcade/stats is an
    # admin-only screen, but it is named here like any other so a hard load or a
    # pasted URL reaches the app at all; the guarding is the route's job on the
    # client and the admin controller's job on the server.
    get "/arcade" => "arcade_page#index"
    get "/arcade/g/:slug" => "arcade_page#index"
    get "/arcade/stats" => "arcade_page#index"

    # JSON API. Namespaced under /api so it can never collide with a game slug.
    get "/arcade/api/games" => "arcade#index"
    get "/arcade/api/games/:slug" => "arcade#show"
    post "/arcade/api/games/:slug/runs" => "arcade#start_run"
    post "/arcade/api/runs/:token" => "arcade#submit_score"
    delete "/arcade/api/scores/:id" => "arcade#destroy_score"

    # Admin JSON lives with the rest of the plugin's API rather than under
    # /admin/plugins, so it can never shadow Discourse's own plugin routes.
    # AdminController already demands an admin, so no extra constraint.
    get "/arcade/api/admin/games" => "admin_arcade#index"
    put "/arcade/api/admin/games/:id" => "admin_arcade#update"
    get "/arcade/api/admin/stats" => "admin_arcade#stats"

    # And the page itself. Rails only serves /admin/plugins/:plugin_id and
    # /settings, so a child route of the admin SPA works when clicked but 404s on
    # a hard load or a pasted URL until it is named here.
    get "/admin/plugins/discourse-arcade/games" => "admin/plugins#show"
  end
end
