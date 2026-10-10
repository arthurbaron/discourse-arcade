# frozen_string_literal: true

# What a member sees on the day the boards reset, and on the season page. The
# moment that matters most is the first visit after a month rolls over: a board
# that suddenly reads "no scores" has to explain itself, or it looks like every
# record on the arcade was wiped.

require "rails_helper"

RSpec.describe "Arcade months and season", type: :system do
  fab!(:player) { Fabricate(:user) }
  fab!(:rival) { Fabricate(:user) }
  fab!(:third) { Fabricate(:user) }

  let!(:game) do
    ArcadeGame.create!(
      slug: "testgame",
      name: "Test Game",
      tagline: "A game for the specs",
      entry_path: "twentyfortyeight/index.html",
      score_direction: "high",
      score_unit: "points",
      max_plausible_score: 100_000,
      min_run_seconds: 0,
    )
  end

  # Mid last month, and a minute ago: neither can land in the wrong month
  # whatever day this runs.
  let(:last_month) do
    month = ArcadePeriod.previous_month
    ArcadePeriod.zone.local(month.year, month.month, 15, 12)
  end

  def add_score(user, value, at:)
    run = ArcadeRun.issue!(user, game)
    ArcadeScore.create!(
      user_id: user.id,
      arcade_game_id: game.id,
      arcade_run_id: run.id,
      score: value,
      created_at: at,
    )
  end

  before do
    SiteSetting.arcade_enabled = true
    ArcadeRecordHolders.clear!
    sign_in(player)
  end

  it "explains an empty board instead of looking wiped" do
    add_score(rival, 9_000, at: last_month)
    add_score(third, 12_000, at: last_month - 2.months)

    visit "/arcade/g/#{game.slug}"

    side = find(".arcade-game-side")
    expect(side).to have_text(ArcadePeriod.label(ArcadePeriod.current_month))
    expect(side).to have_text("No scores yet this month")
    expect(side).to have_text("Last month #{rival.username} won with 9000")
    expect(side.find(".arcade-all-time")).to have_text("All-time record 12000 by #{third.username}")
  end

  # The record has one fixed place on every game page. It was once hidden when
  # this month's leader held it, to avoid repeating a name, and that left games
  # with nowhere the record could be found at all.
  it "always shows the all-time record, even when this month's leader holds it" do
    add_score(rival, 50, at: last_month)
    add_score(player, 400, at: 1.minute.ago)

    visit "/arcade/g/#{game.slug}"

    expect(page).to have_css(".arcade-lb-row.is-you")
    expect(page).to have_text("To beat this month 400")
    expect(find(".arcade-all-time")).to have_text("All-time record 400 by #{player.username}")
  end

  it "keeps the all-time record on the arcade card, under this month's leader" do
    add_score(rival, 9_000, at: last_month)
    add_score(player, 400, at: 1.minute.ago)
    ArcadeRecordHolders.clear!

    visit "/arcade"

    card = find(".arcade-card", text: game.name)
    chip = card.find(".arcade-chip-record")
    expect(chip).to have_text(player.username)
    expect(chip).to have_text("400")
    expect(card.find(".arcade-card-record")).to have_text("All-time record 9000 by #{rival.username}")
  end

  it "names the month on the arcade and leads to the season table" do
    [[player, 30], [rival, 20], [third, 10]].each do |user, value|
      add_score(user, value, at: 1.minute.ago)
    end
    ArcadeRecordHolders.clear!

    visit "/arcade"
    expect(find(".arcade-intro")).to have_text(ArcadePeriod.label(ArcadePeriod.current_month))

    find(".arcade-season-link").click

    expect(page).to have_css(".arcade-season-page")
    expect(page).to have_text("Season #{ArcadePeriod.season_label(ArcadePeriod.current_season)}")
    expect(page).to have_text("score 10, 7, 5, 3 and 1 points")

    rows = all(".arcade-season-row:not(.arcade-season-header)")
    expect(rows.length).to eq(3)
    expect(rows.first).to have_text(player.username)
    expect(rows.first).to have_text("10")
    expect(rows.first[:class]).to include("is-you")
  end

  it "says so when nothing has counted yet" do
    add_score(rival, 20, at: 1.minute.ago)

    visit "/arcade/season"

    expect(page).to have_text("No standings yet")
    expect(page).to have_no_css(".arcade-season-table")
  end

  it "shows last month's top five on the season page" do
    [[rival, 30], [player, 20], [third, 10]].each { |user, value| add_score(user, value, at: last_month) }
    ArcadeRecordHolders.clear!

    visit "/arcade/season"

    card = find(".arcade-month-card", text: ArcadePeriod.label(ArcadePeriod.previous_month))
    rows = card.all(".arcade-lb-row")
    expect(rows.map { |row| row.find(".arcade-lb-name").text }).to eq(
      [rival.username, player.username, third.username],
    )
    expect(rows[0]).to have_text("10 pts")
    expect(rows[1][:class]).to include("is-you")

    # This month has started but is not a result yet, so it gets no card.
    expect(page).to have_no_css(".arcade-month-card", text: ArcadePeriod.label(ArcadePeriod.current_month))
  end
end
