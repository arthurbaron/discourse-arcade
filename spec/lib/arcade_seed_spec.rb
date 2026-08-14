# frozen_string_literal: true

# The seed task runs on every deploy, so the one thing it must never do is undo a
# choice made in admin. It refreshes a game's metadata but sets `enabled` only
# when creating the row.

require "rails_helper"

RSpec.describe ArcadeGame, type: :task do
  before do
    SiteSetting.arcade_enabled = true

    # Plugin rake files are registered on a rakelib path and only read when rake
    # itself runs, so in a spec process the task does not exist yet. Loading it
    # once is enough; clearing all tasks first would drop the registration.
    unless Rake::Task.task_defined?("arcade:seed")
      Rake::Task.define_task(:environment)
      load Rails.root.join("plugins/discourse-arcade/lib/tasks/arcade.rake").to_s
    end
  end

  def seed
    Rake::Task["arcade:seed"].reenable
    capture_stdout { Rake::Task["arcade:seed"].invoke }
  end

  it "creates the catalogue" do
    seed
    expect(ArcadeGame.count).to be >= 10
    expect(ArcadeGame.pluck(:slug)).to include("2048", "penalty", "debris")
  end

  it "brings the newest games in switched off, ready to be turned on by hand" do
    seed
    expect(ArcadeGame.find_by(slug: "debris").enabled).to eq(false)
    expect(ArcadeGame.find_by(slug: "darts").enabled).to eq(false)
    expect(ArcadeGame.find_by(slug: "stack").enabled).to eq(false)
    expect(ArcadeGame.find_by(slug: "penalty").enabled).to eq(true)
  end

  it "leaves a game an admin switched off switched off" do
    seed
    ArcadeGame.find_by(slug: "penalty").update!(enabled: false)

    seed

    expect(ArcadeGame.find_by(slug: "penalty").enabled).to eq(false)
  end

  it "leaves a game an admin switched on switched on" do
    seed
    ArcadeGame.find_by(slug: "debris").update!(enabled: true)

    seed

    expect(ArcadeGame.find_by(slug: "debris").enabled).to eq(true)
  end

  it "still refreshes everything else" do
    seed
    penalty = ArcadeGame.find_by(slug: "penalty")
    penalty.update!(tagline: "stale", max_plausible_score: 1)

    seed

    penalty.reload
    expect(penalty.tagline).not_to eq("stale")
    expect(penalty.max_plausible_score).to be > 1
  end

  it "keeps every score" do
    seed
    game = ArcadeGame.find_by(slug: "penalty")
    user = Fabricate(:user)
    run = ArcadeRun.issue!(user, game)
    ArcadeScore.create!(
      user_id: user.id,
      arcade_game_id: game.id,
      arcade_run_id: run.id,
      score: 7,
    )

    seed

    expect(game.reload.arcade_scores.accepted.count).to eq(1)
  end
end
