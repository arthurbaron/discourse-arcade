# frozen_string_literal: true

class ArcadeController < ApplicationController
  requires_login

  before_action :ensure_arcade_enabled

  # GET /arcade/api/games
  def index
    games = ArcadeGame.listed.to_a

    # One query for all of this user's scores this month, then pick the best per
    # game in Ruby, because "best" depends on each game's score direction.
    my_scores =
      ArcadeScore
        .accepted
        .where(user_id: current_user.id, arcade_game_id: games.map(&:id))
        .where(created_at: ArcadePeriod.current_range)
        .group_by(&:arcade_game_id)

    render json: {
             period: period_json,
             games:
               games.map do |game|
                 mine = (my_scores[game.id] || [])
                 best =
                   if game.higher_is_better?
                     mine.max_by { |s| [s.score, -s.created_at.to_i] }
                   else
                     mine.min_by { |s| [s.score, s.created_at.to_i] }
                   end

                 # This month's leader is one small query per game. The game
                 # list is a handful of rows, so this stays cheap.
                 holder = game.leaderboard(limit: 1).first

                 {
                   slug: game.slug,
                   name: game.name,
                   tagline: game.tagline,
                   thumbnail_url: game.thumbnail_url,
                   score_unit: game.score_unit,
                   score_direction: game.score_direction,
                   plays_count: game.plays_count,
                   your_best: best&.score,
                   record: holder ? serialize_entry(holder, 1) : nil,
                   # The card showed the all-time record before boards went
                   # monthly, and it stays on the card now they have.
                   all_time_record: serialize_first(game.leaderboard(limit: 1, within: nil)),
                 }
               end,
           }
  end

  # GET /arcade/api/games/:slug
  def show
    game = find_game!

    render json: {
             game: {
               slug: game.slug,
               name: game.name,
               tagline: game.tagline,
               play_url: game.play_url,
               # The frame appends this to the game URL, and the game passes it
               # on to its own scripts, so a deploy busts every layer of cache.
               assets_version: ArcadeAssetsVersion.current,
               score_unit: game.score_unit,
               score_direction: game.score_direction,
               plays_count: game.plays_count,
             },
             period: period_json,
             leaderboard: serialize_leaderboard(game),
             your_best: game.personal_best_for(current_user.id)&.score,
             your_rank: game.rank_for(current_user.id),
             # The board resets monthly, so these two are what keep a great
             # score in view once its month is over. Without the all-time line
             # the reset reads to whoever set the record as "your record is gone".
             all_time_record: serialize_first(game.leaderboard(limit: 1, within: nil)),
             last_month_winner:
               serialize_first(
                 game.leaderboard(limit: 1, within: ArcadePeriod.range(ArcadePeriod.previous_month)),
               ),
             can_moderate: current_user.staff?,
           }
  end

  # GET /arcade/api/season
  def season
    standings = ArcadeSeason.standings
    mark_you = ->(rows) { rows.map { |row| row.merge(is_you: row[:user_id] == current_user.id) } }

    # The cached table is shared by everyone, so "you" is added per request on a
    # copy rather than stored in it.
    render json:
             standings.merge(
               standings: mark_you.call(standings[:standings]),
               months: standings[:months].map { |month| month.merge(top: mark_you.call(Array(month[:top]))) },
             )
  end

  # POST /arcade/api/games/:slug/runs
  def start_run
    game = find_game!

    RateLimiter.new(
      current_user,
      "arcade-run",
      SiteSetting.arcade_max_runs_per_hour,
      1.hour,
    ).performed!

    run = ArcadeRun.issue!(current_user, game)

    render json: { token: run.token }
  end

  # POST /arcade/api/runs/:token
  def submit_score
    result =
      ArcadeScoreSubmission.call(
        user: current_user,
        token: params[:token],
        raw_score: params[:score],
      )

    unless result.ok?
      return render json: { error: result.error }, status: 422
    end

    score = result.score
    game = score.arcade_game
    month_best = game.personal_best_for(current_user.id)
    all_time_best = game.personal_best_for(current_user.id, within: nil)

    render json: {
             score: score.score,
             # Two different pieces of news. A first score of the month is always
             # the month's best, so announcing it as a "personal best" would cry
             # wolf on the 1st of every month.
             is_personal_best: all_time_best&.id == score.id,
             is_month_best: month_best&.id == score.id,
             your_best: month_best&.score,
             your_rank: game.rank_for(current_user.id),
             # The page loaded its count before this run, so send the new one or
             # the stat sits there reading zero next to a score that just landed.
             plays_count: game.plays_count,
             leaderboard: serialize_leaderboard(game),
             all_time_record: serialize_first(game.leaderboard(limit: 1, within: nil)),
           }
  end

  # DELETE /arcade/api/scores/:id
  def destroy_score
    raise Discourse::InvalidAccess unless current_user.staff?

    score = ArcadeScore.find(params[:id])
    score.reject!(reason: params[:reason].presence || "Removed by staff", moderator: current_user)
    ArcadeRecordHolders.clear!

    render json: { success: true, leaderboard: serialize_leaderboard(score.arcade_game) }
  end

  private

  def ensure_arcade_enabled
    raise Discourse::NotFound unless SiteSetting.arcade_enabled
  end

  def find_game!
    ArcadeGame.listed.find_by(slug: params[:slug]) || raise(Discourse::NotFound)
  end

  def serialize_leaderboard(game)
    size = SiteSetting.arcade_leaderboard_size.to_i
    game.leaderboard(limit: size).each_with_index.map do |score, index|
      serialize_entry(score, index + 1)
    end
  end

  def serialize_first(board)
    entry = board.first
    entry ? serialize_entry(entry, 1) : nil
  end

  def period_json
    month = ArcadePeriod.current_month
    {
      key: ArcadePeriod.key(month),
      label: ArcadePeriod.label(month),
      season_label: ArcadePeriod.season_label(ArcadePeriod.season_of(month)),
    }
  end

  def serialize_entry(score, rank)
    user = score.user

    {
      id: score.id,
      rank: rank,
      score: score.score,
      username: user&.username,
      name: user&.name,
      # Resolved server side so the template can drop it straight into an img.
      avatar_url: user&.avatar_template&.gsub("{size}", "48"),
      created_at: score.created_at,
      is_you: score.user_id == current_user&.id,
    }
  end
end
