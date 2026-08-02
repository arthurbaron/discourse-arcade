# frozen_string_literal: true

# The arcade raised discourse.deprecated-resolver-normalization on every page
# load, which shows up as a red admin notice on the forum.
#
# The cause was mundane. Ember asks the resolver for `template:arcade/index`, the
# template file was named `arcade-index.hbs`, and the resolver found it only via
# its last-resort "try it all dasherized" candidate. Finding a template under any
# name other than the one asked for is what triggers the deprecation, so the fix
# was renaming two files into a nested directory rather than the frontend port I
# had assumed it needed.
#
# This spec reads the browser console, because a deprecation is invisible to a
# spec that only checks the page rendered.

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

  def resolver_deprecations(logger)
    logger.logs.filter_map do |entry|
      entry[:message] if entry[:message].to_s.include?("no longer permitted")
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
      expect(resolver_deprecations(logger)).to eq([])
    end
  end
end
