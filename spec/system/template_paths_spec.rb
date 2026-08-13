# frozen_string_literal: true

# The arcade has raised two different Ember deprecations, both of which surface
# as a red admin notice on the forum and neither of which any "did the page
# render" spec can see. So this one reads the browser console.
#
# First: discourse.deprecated-resolver-normalization. Ember asks the resolver for
# `template:arcade/index`, the template file was named `arcade-index.hbs`, and
# the resolver found it only via its last-resort "try it all dasherized"
# candidate. Finding a template under any name other than the one asked for is
# what triggers it, so the fix was renaming files into nested directories rather
# than the frontend port I had assumed it needed.
#
# Second: discourse.hbs-extension. The .hbs extension itself is deprecated and
# support is being removed during the 2026.8 cycle, which is the release track
# this forum runs, so this one was on a clock rather than merely untidy. Every
# template is now .gjs.

require "rails_helper"

RSpec.describe "Arcade template paths", type: :system do
  fab!(:player) { Fabricate(:user) }

  let!(:game) do
    ArcadeGame.create!(
      slug: "alpha",
      name: "Alpha",
      entry_path: "alpha/index.html",
      max_plausible_score: 1_000,
      min_run_seconds: 0,
      position: 1,
    )
  end

  before do
    SiteSetting.arcade_enabled = true
    sign_in(player)
  end

  def deprecations_matching(logger, needle)
    logger.logs.filter_map do |entry|
      entry[:message] if entry[:message].to_s.include?(needle)
    end
  end

  it "resolves both arcade templates by the name Ember asks for" do
    with_logs do |logger|
      visit "/arcade"
      expect(page).to have_css(".arcade-card")

      visit "/arcade/g/alpha"
      expect(page).to have_css(".arcade-frame")

      # Both pages rendered, so the templates were found. The point of this spec
      # is that they were found under the requested name and not a fallback.
      expect(deprecations_matching(logger, "no longer permitted")).to eq([])
    end
  end

  it "ships no templates that still use the deprecated .hbs extension" do
    with_logs do |logger|
      visit "/arcade"
      expect(page).to have_css(".arcade-card")

      visit "/arcade/g/alpha"
      expect(page).to have_css(".arcade-frame")

      expect(deprecations_matching(logger, "hbs-extension")).to eq([])
      expect(deprecations_matching(logger, "deprecated .hbs extension")).to eq([])
    end
  end
end
