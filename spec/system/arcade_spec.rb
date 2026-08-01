# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Arcade", type: :system do
  fab!(:player) { Fabricate(:user) }

  let!(:game) do
    ArcadeGame.create!(
      slug: "testgame",
      name: "Test Game",
      tagline: "A game for the specs",
      entry_path: "twentyfortyeight/index.html",
      score_direction: "high",
      score_unit: "points",
      max_plausible_score: 10_000,
      min_run_seconds: 0,
    )
  end

  before do
    SiteSetting.arcade_enabled = true
    sign_in(player)
  end

  it "renders the game grid and opens a game page" do
    visit "/arcade"

    expect(page).to have_css(".arcade-index")

    # The icon has to actually resolve to a sprite symbol. A name FontAwesome
    # has dropped renders an empty box rather than failing loudly.
    expect(page).to have_css(".arcade-head h1 svg.d-icon-gamepad")

    expect(page).to have_css(".arcade-card", count: 1)
    expect(page).to have_content("Test Game")
    expect(page).to have_content("A game for the specs")

    find(".arcade-card").click

    expect(page).to have_css(".arcade-game-page")
    expect(page).to have_css(".arcade-frame")
    expect(page).to have_content("Leaderboard")
    expect(page).to have_content("No scores yet")
    expect(page).to have_button("Play Test Game")
  end

  it "saves a real score through the frame and updates the leaderboard" do
    visit "/arcade/g/#{game.slug}"

    find(".arcade-frame-start").click
    expect(page).to have_css(".arcade-frame-canvas")

    # Play the game out inside the sandboxed frame until it reports game over.
    within_frame(find(".arcade-frame-canvas")) do
      page.execute_script(<<~JS)
        (function () {
          var dirs = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"];
          var over = document.getElementById("over");
          var moves = 0;
          while (moves < 5000 && !over.classList.contains("visible")) {
            window.dispatchEvent(
              new KeyboardEvent("keydown", {
                key: dirs[Math.floor(Math.random() * 4)],
              })
            );
            moves++;
          }
        })();
      JS
    end

    expect(page).to have_css(".arcade-frame-score")
    expect(page).to have_button("Play again")

    # A first score is always a personal best, so the badge and its star show.
    expect(page).to have_css(".arcade-frame-badge svg.d-icon-star")
    expect(page).to have_css(".arcade-lb-row.is-you")

    score = ArcadeScore.find_by(user_id: player.id, arcade_game_id: game.id)
    expect(score).to be_present
    expect(score.score).to be > 0
    expect(page).to have_content(score.score.to_s)
    expect(ArcadeRun.find(score.arcade_run_id).consumed?).to eq(true)
  end

  it "shows an existing score on the leaderboard" do
    run = ArcadeRun.issue!(player, game)
    ArcadeScore.create!(
      user_id: player.id,
      arcade_game_id: game.id,
      arcade_run_id: run.id,
      score: 742,
    )

    visit "/arcade/g/#{game.slug}"

    expect(page).to have_css(".arcade-lb-row.is-you")
    expect(page).to have_content("742")
    expect(page).to have_content(player.username)
  end
end
