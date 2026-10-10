# frozen_string_literal: true

# The flair renders on every post in every topic, so it is worth proving in a
# real browser that it appears for a record holder, stays away from everyone
# else, and disappears the moment the setting is turned off.

require "rails_helper"

RSpec.describe "Arcade record flair", type: :system do
  fab!(:holder) { Fabricate(:user) }
  fab!(:nobody) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, user: holder) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: holder) }
  fab!(:second_post) { Fabricate(:post, topic: topic, user: nobody) }

  let!(:first_game) do
    ArcadeGame.create!(
      slug: "alpha",
      name: "Alpha",
      entry_path: "alpha/index.html",
      max_plausible_score: 10_000,
      min_run_seconds: 0,
      position: 1,
    )
  end

  let!(:second_game) do
    ArcadeGame.create!(
      slug: "beta",
      name: "Beta",
      entry_path: "beta/index.html",
      max_plausible_score: 10_000,
      min_run_seconds: 0,
      position: 2,
    )
  end

  def record_score(user, game, value)
    run = ArcadeRun.issue!(user, game)
    ArcadeScore.create!(
      user_id: user.id,
      arcade_game_id: game.id,
      arcade_run_id: run.id,
      score: value,
    )
  end

  before do
    SiteSetting.arcade_enabled = true
    SiteSetting.arcade_show_record_flair = true
    sign_in(holder)
  end

  # The flair renders next to the username in a wrapper outlet, and the wrong
  # plugin API there replaces the username instead of sitting beside it. That
  # failure looks fine to a spec that only checks the flair appeared, so every
  # example below also checks the username is still on the page.
  it "leaves both usernames in place" do
    record_score(holder, first_game, 900)
    ArcadeRecordHolders.clear!

    visit topic.relative_url

    expect(page).to have_css("#post_1 .arcade-record-flair")
    expect(find("#post_1 .names")).to have_text(holder.username)
    expect(find("#post_2 .names")).to have_text(nobody.username)
  end

  it "shows a trophy and a count on the record holder's post only" do
    record_score(holder, first_game, 900)
    record_score(nobody, first_game, 100)
    record_score(holder, second_game, 700)
    ArcadeRecordHolders.clear!

    visit topic.relative_url

    expect(page).to have_css("#post_1 .arcade-record-flair")
    expect(find("#post_1 .names")).to have_text(holder.username)
    expect(find("#post_1 .arcade-record-flair-count")).to have_text("2")
    expect(find("#post_1 .arcade-record-flair")["title"]).to eq(
      "Arcade record holder: Alpha, Beta",
    )

    # Second place on one game and nothing on the other earns nothing.
    expect(page).to have_css("#post_2")
    expect(page).not_to have_css("#post_2 .arcade-record-flair")
  end

  it "counts only the games actually led" do
    record_score(holder, first_game, 900)
    ArcadeRecordHolders.clear!

    visit topic.relative_url

    expect(find("#post_1 .arcade-record-flair-count")).to have_text("1")
  end

  it "links through to the arcade" do
    record_score(holder, first_game, 900)
    ArcadeRecordHolders.clear!

    visit topic.relative_url

    expect(find("#post_1 .arcade-record-flair")["href"]).to end_with("/arcade")
  end

  it "shows nothing at all when the setting is off" do
    record_score(holder, first_game, 900)
    ArcadeRecordHolders.clear!
    SiteSetting.arcade_show_record_flair = false

    visit topic.relative_url

    expect(page).to have_css("#post_1")
    expect(page).not_to have_css(".arcade-record-flair")
  end

  it "shows nothing when nobody holds a record" do
    visit topic.relative_url

    expect(page).to have_css("#post_1")
    expect(page).not_to have_css(".arcade-record-flair")
  end
end
