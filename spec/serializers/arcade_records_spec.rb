# frozen_string_literal: true

require "rails_helper"

RSpec.describe PostSerializer do
  fab!(:holder) { Fabricate(:user) }
  fab!(:nobody) { Fabricate(:user) }
  fab!(:holder_post) { Fabricate(:post, user: holder) }
  fab!(:other_post) { Fabricate(:post, user: nobody) }

  let!(:game) do
    ArcadeGame.create!(
      slug: "a",
      name: "Game A",
      entry_path: "a/index.html",
      max_plausible_score: 10_000,
      min_run_seconds: 0,
    )
  end

  before do
    SiteSetting.arcade_enabled = true
    SiteSetting.arcade_show_record_flair = true

    run = ArcadeRun.issue!(holder, game)
    ArcadeScore.create!(
      user_id: holder.id,
      arcade_game_id: game.id,
      arcade_run_id: run.id,
      score: 500,
    )

    ArcadeRecordHolders.clear!
  end

  def serialize(post)
    PostSerializer.new(post, scope: Guardian.new(holder), root: false).as_json
  end

  it "lists the games a record holder leads" do
    expect(serialize(holder_post)[:arcade_records]).to eq(["Game A"])
  end

  # The field is left out rather than sent as an empty array, so the vast
  # majority of posts carry nothing extra at all.
  it "leaves the field out for someone holding nothing" do
    expect(serialize(other_post)).not_to have_key(:arcade_records)
  end

  it "leaves the field out when the flair setting is off" do
    SiteSetting.arcade_show_record_flair = false
    expect(serialize(holder_post)).not_to have_key(:arcade_records)
  end

  it "leaves the field out when the arcade is off" do
    SiteSetting.arcade_enabled = false
    expect(serialize(holder_post)).not_to have_key(:arcade_records)
  end
end
