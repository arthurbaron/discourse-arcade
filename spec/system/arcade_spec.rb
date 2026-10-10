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

  # Waits for a fresh game whose script has loaded, then plays it to game over.
  #
  # Both halves of the wait were caught failing a full suite run. #over sits in
  # the page's static markup, so it exists before game.js does, and keys sent in
  # that gap reach nothing: the first run could end without a single move. And
  # Play again keeps the same iframe and only swaps its document, so for a moment
  # the old, finished game is still there: the second run could see its "game
  # over", decide it was done, and leave the new game untouched at zero. Waiting
  # for the frame to merely exist covered neither.
  def play_until_over
    within_frame(find(".arcade-frame-canvas")) do
      ready = false
      100.times do
        begin
          ready =
            page.evaluate_script(
              "!!window.Game2048 && !document.getElementById('over').classList.contains('visible')",
            )
        rescue Playwright::Error
          # The frame's document is being replaced mid-check; try again.
          ready = false
        end
        break if ready
        sleep 0.1
      end
      expect(ready).to eq(true)

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
  end

  it "renders the game grid and opens a game page" do
    visit "/arcade"

    expect(page).to have_css(".arcade-index")

    expect(find(".arcade-head h1")).to have_text("🎮")

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
    play_until_over

    # The score goes out over postMessage and then to the server before this
    # appears, so it needs more room than the default wait when the whole suite
    # is competing for the machine.
    expect(page).to have_css(".arcade-frame-score", wait: 20)
    expect(page).to have_button("Play again")

    # A first score is always a personal best, so the badge and its star show.
    expect(page).to have_css(".arcade-frame-badge svg.d-icon-star")
    expect(page).to have_css(".arcade-lb-row.is-you")

    # The plays stat was rendered before the run, so it has to be refreshed or
    # it reads zero next to a score that just landed.
    expect(find(".arcade-stats")).to have_text("1")

    score = ArcadeScore.find_by(user_id: player.id, arcade_game_id: game.id)
    expect(score).to be_present
    expect(score.score).to be > 0
    expect(page).to have_content(score.score.to_s)
    expect(ArcadeRun.find(score.arcade_run_id).consumed?).to eq(true)
  end

  # Play again is a different code path from the first run and nothing covered
  # it, which let a real regression ship: the frame cached its iframe from a
  # didInsert that only fires on insertion, and Play again reuses the same
  # element with a new src. Every run after the first silently dropped its
  # score and never showed the result overlay. One run being green said nothing
  # about two.
  it "saves the score from a second run in the same visit" do
    visit "/arcade/g/#{game.slug}"

    2.times do |attempt|
      find(attempt.zero? ? ".arcade-frame-start" : "button", text: /Play/).click
      expect(page).to have_css(".arcade-frame-canvas")

      play_until_over

      # The overlay reappearing is half the bug: without it there is no way back
      # into the game from the game over screen.
      expect(page).to have_css(".arcade-frame-score", wait: 20)
      expect(page).to have_button("Play again")
      expect(ArcadeScore.where(user_id: player.id).count).to eq(attempt + 1)
    end

    expect(find(".arcade-stats")).to have_text("2")
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
