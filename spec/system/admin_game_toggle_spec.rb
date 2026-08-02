# frozen_string_literal: true

# The admin page for switching games on and off. Worth a browser spec rather than
# only a request spec, because the whole point of the feature is that Arthur can
# do it without a console, and a working endpoint behind a page that fails to
# render is no use to him.

require "rails_helper"

RSpec.describe "Admin game toggle", type: :system do
  fab!(:admin)
  fab!(:player) { Fabricate(:user) }

  let!(:penalty) do
    ArcadeGame.create!(
      slug: "penalty",
      name: "Penalty",
      tagline: "Beat the keeper.",
      entry_path: "penalty/index.html",
      thumbnail: "penalty.svg",
      max_plausible_score: 500,
      min_run_seconds: 0,
      position: 1,
    )
  end

  let!(:recall) do
    ArcadeGame.create!(
      slug: "recall",
      name: "Recall",
      tagline: "Repeat the sequence.",
      entry_path: "recall/index.html",
      thumbnail: "recall.svg",
      max_plausible_score: 100,
      min_run_seconds: 0,
      position: 2,
    )
  end

  before do
    SiteSetting.arcade_enabled = true
    sign_in(admin)
  end

  def rows
    all(".arcade-admin-games__row")
  end

  # The switch's button is visually hidden and the label is what you actually
  # click, which is how Discourse's own page object drives it too.
  def flip(row)
    within(row) { find("label.d-toggle-switch__label").click }
  end

  it "lists the games with their thumbnails and switches one off" do
    visit "/admin/plugins/discourse-arcade/games"

    expect(page).to have_css(".arcade-admin-games__row", count: 2)
    expect(rows.first).to have_text("Penalty")
    expect(rows.first).to have_text("Beat the keeper.")
    expect(rows.first).to have_css("img")

    flip(rows.first)

    # The row goes visibly quiet, and the database agrees.
    expect(page).to have_css(".arcade-admin-games__row--off")
    try_until_success { expect(penalty.reload.enabled).to eq(false) }
  end

  it "takes a switched off game out of the arcade and leaves the others" do
    penalty.update!(enabled: false)

    visit "/arcade"

    expect(page).to have_css(".arcade-card", count: 1)
    expect(page).to have_text("Recall")
    expect(page).not_to have_text("Penalty")
  end

  it "switches one back on" do
    recall.update!(enabled: false)

    visit "/admin/plugins/discourse-arcade/games"
    expect(page).to have_css(".arcade-admin-games__row", count: 2)

    off_row = find(".arcade-admin-games__row--off")
    flip(off_row)

    try_until_success { expect(recall.reload.enabled).to eq(true) }
    expect(page).not_to have_css(".arcade-admin-games__row--off")
  end
end
