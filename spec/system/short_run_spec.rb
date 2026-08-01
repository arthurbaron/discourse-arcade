# frozen_string_literal: true

# Regression guard for a production report: members saw "That run was too short
# to be real" while holding a good score.
#
# The cause was a flat minimum duration applied to every submission. Several of
# these games end legitimately in about a second: Keepie Uppie the moment you
# miss the ball, Dribble on the first defender. Those runs were rejected, so real
# play was thrown away, and because the overlay shows the error in place of the
# result it read as though an earlier high score had been deleted.

require "rails_helper"

RSpec.describe "A legitimately short run", type: :system do
  fab!(:player) { Fabricate(:user) }

  let!(:game) do
    ArcadeGame.create!(
      slug: "keepie",
      name: "Keepie Uppie",
      entry_path: "keepie/index.html",
      score_unit: "touches",
      max_plausible_score: 2_000,
      min_run_seconds: 1,
      position: 1,
    )
  end

  before do
    SiteSetting.arcade_enabled = true
    sign_in(player)
  end

  it "stores a scoreless run that was over in a second" do
    visit "/arcade/g/keepie"

    find(".arcade-frame-start").click
    expect(page).to have_css(".arcade-frame-canvas")
    expect(page).to have_css(".arcade-frame-result", wait: 30)

    # Never touching the ball is bad play, not a forgery.
    expect(page).not_to have_css(".arcade-frame-error")
    expect(page).to have_css(".arcade-frame-score")

    scores = ArcadeScore.where(user_id: player.id)
    expect(scores.count).to eq(1)
    expect(scores.first.score).to eq(0)
  end

  it "leaves an earlier good score untouched" do
    earlier = ArcadeRun.issue!(player, game)
    ArcadeScore.create!(
      user_id: player.id,
      arcade_game_id: game.id,
      arcade_run_id: earlier.id,
      score: 42,
      duration_seconds: 65,
    )

    visit "/arcade/g/keepie"

    find(".arcade-frame-start").click
    expect(page).to have_css(".arcade-frame-canvas")
    expect(page).to have_css(".arcade-frame-result", wait: 30)

    # The new run stores its 0 and the 42 keeps top spot.
    expect(ArcadeScore.where(user_id: player.id).pluck(:score).sort).to eq([0, 42])
    expect(find(".arcade-lb-row.is-you")).to have_text("42")
  end
end
