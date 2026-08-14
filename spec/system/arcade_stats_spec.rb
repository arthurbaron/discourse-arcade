# frozen_string_literal: true

# The arithmetic is covered in spec/lib/arcade_stats_spec.rb. What is left to
# check here is the part a unit test cannot see: that the page renders the
# numbers it was handed, and that a member can neither see the way in nor reach
# the screen by typing the URL.

require "rails_helper"

RSpec.describe "Arcade statistics", type: :system do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:member) { Fabricate(:user) }

  fab!(:game) do
    ArcadeGame.create!(
      slug: "testgame",
      name: "Test Game",
      tagline: "A game for the specs",
      entry_path: "twentyfortyeight/index.html",
      score_unit: "points",
      position: 1,
    )
  end

  before { SiteSetting.arcade_enabled = true }

  def add_score(user, score, at:, duration: 45)
    run = ArcadeRun.create!(user_id: user.id, arcade_game_id: game.id, token: SecureRandom.hex(16))
    ArcadeScore.create!(
      user_id: user.id,
      arcade_game_id: game.id,
      arcade_run_id: run.id,
      score: score,
      duration_seconds: duration,
      created_at: at,
    )
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "offers the way in from the arcade and shows the numbers" do
      add_score(admin, 500, at: Time.zone.now - 1.hour)
      add_score(member, 900, at: Time.zone.now - 2.hours)
      ArcadeRecordHolders.clear!

      visit "/arcade"
      expect(page).to have_css(".arcade-stats-link")

      find(".arcade-stats-link").click
      expect(page).to have_css(".arcade-stats-page")

      # Two plays today by two different people.
      tiles = find(".arcade-stat-tiles")
      expect(tiles).to have_text("2")

      row = find(".arcade-stat-table tbody tr")
      expect(row).to have_text("Test Game")
      # Median of a single 45 second pair of runs, formatted.
      expect(row).to have_text("45s")
      # Best score respects the game's direction, so the higher one wins here.
      expect(row).to have_text("900")

      # The record holder is whoever tops the board, same source as the flair.
      expect(find(".arcade-trophy-list")).to have_text(member.username)

      # Both charts render a bar column per bucket.
      expect(page).to have_css(".arcade-stat-block", minimum: 4)
      expect(page).to have_css(".arcade-bars", count: 2)
      expect(page).to have_css(".arcade-bar-col", count: ArcadeStats::TREND_DAYS + 7)
    end

    it "says so plainly when nothing has been played" do
      visit "/arcade/stats"

      expect(page).to have_css(".arcade-stats-page")
      expect(page).to have_content("Nothing has been played yet")
      expect(page).to have_no_css(".arcade-stat-table")
    end

    it "keeps a switched-off game in the table rather than hiding its history" do
      add_score(admin, 100, at: Time.zone.now - 1.hour)
      game.update!(enabled: false)

      visit "/arcade/stats"

      row = find(".arcade-stat-table tbody tr")
      expect(row).to have_text("Test Game")
      expect(row[:class]).to include("is-off")
    end
  end

  context "as an ordinary member" do
    before { sign_in(member) }

    it "does not offer the link" do
      visit "/arcade"

      expect(page).to have_css(".arcade-index")
      expect(page).to have_no_css(".arcade-stats-link")
    end

    # The link being hidden is not a guard. Typing the URL has to fail too.
    it "is turned away from the URL" do
      visit "/arcade/stats"

      expect(page).to have_css(".arcade-index")
      expect(page).to have_no_css(".arcade-stats-page")
    end

    # The endpoint itself refusing a member is checked where it belongs, against
    # the controller: spec/requests/admin_arcade_controller_spec.rb.
  end
end
