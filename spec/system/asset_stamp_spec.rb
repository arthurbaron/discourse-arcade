# frozen_string_literal: true

# Game files live under /plugins/, which production nginx serves with a year of
# "never ask again" caching. The only thing standing between a phone and stale
# game code is the version stamp travelling host -> frame URL -> every asset
# the game loads, so this walks that whole chain in a real browser.

require "rails_helper"

RSpec.describe "Game asset version stamp", type: :system do
  fab!(:player) { Fabricate(:user) }

  let!(:game) do
    ArcadeGame.create!(
      slug: "testgame",
      name: "Test Game",
      tagline: "A game for the specs",
      entry_path: "snake/index.html",
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

  # Link elements, not document.styleSheets: a sheet only shows up there once
  # it has loaded, and these specs must not depend on how fast that goes. The
  # poll covers the parser still being on its way to the body-end script tags.
  def asset_urls(minimum:)
    collect = <<~JS
      [].concat(
        Array.from(document.scripts, function (s) { return s.src; }),
        Array.from(
          document.querySelectorAll("link[rel=stylesheet]"),
          function (l) { return l.href; }
        )
      ).filter(Boolean)
    JS

    urls = []
    40.times do
      urls = page.evaluate_script(collect)
      break if urls.length >= minimum
      sleep 0.1
    end
    urls
  end

  it "stamps the frame URL and every asset the game loads from it" do
    visit "/arcade/g/#{game.slug}"
    find(".arcade-frame-start").click

    frame = find(".arcade-frame-canvas")
    expect(frame[:src]).to include("v=#{ArcadeAssetsVersion.current}")

    within_frame(frame) do
      # The shared stylesheet, the shared helper, and the game itself.
      urls = asset_urls(minimum: 3)
      expect(urls.length).to eq(3)
      urls.each { |url| expect(url).to include("?v=#{ArcadeAssetsVersion.current}") }
    end
  end

  it "loads bare when opened by hand, without a stamp" do
    visit "/plugins/discourse-arcade/games/snake/index.html"

    urls = asset_urls(minimum: 3)
    expect(urls.length).to eq(3)
    urls.each { |url| expect(url).not_to include("v=") }
  end

  it "drops a stamp that is not plain hex rather than writing it into the page" do
    visit "/plugins/discourse-arcade/games/snake/index.html?v=%22%3E%3Cscript%3E"

    urls = asset_urls(minimum: 3)
    expect(urls.length).to eq(3)
    urls.each { |url| expect(url).not_to include("v=") }
  end
end
