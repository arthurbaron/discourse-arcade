# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminArcadeController do
  fab!(:admin)
  fab!(:moderator)
  fab!(:user)

  let!(:on_game) do
    ArcadeGame.create!(
      slug: "alpha",
      name: "Alpha",
      tagline: "First",
      entry_path: "alpha/index.html",
      max_plausible_score: 1_000,
      min_run_seconds: 0,
      position: 1,
    )
  end

  let!(:off_game) do
    ArcadeGame.create!(
      slug: "beta",
      name: "Beta",
      entry_path: "beta/index.html",
      max_plausible_score: 1_000,
      min_run_seconds: 0,
      enabled: false,
      position: 2,
    )
  end

  before { SiteSetting.arcade_enabled = true }

  describe "#index" do
    it "lists every game, switched on or off" do
      sign_in(admin)
      get "/arcade/api/admin/games.json"

      expect(response.status).to eq(200)
      games = response.parsed_body["games"]

      expect(games.map { |g| g["slug"] }).to eq(%w[alpha beta])
      expect(games.map { |g| g["enabled"] }).to eq([true, false])
    end

    it "reports how many scores each game holds" do
      run = ArcadeRun.issue!(user, on_game)
      ArcadeScore.create!(
        user_id: user.id,
        arcade_game_id: on_game.id,
        arcade_run_id: run.id,
        score: 10,
      )

      sign_in(admin)
      get "/arcade/api/admin/games.json"

      alpha = response.parsed_body["games"].find { |g| g["slug"] == "alpha" }
      expect(alpha["scores_count"]).to eq(1)
    end

    it "refuses a moderator" do
      sign_in(moderator)
      get "/arcade/api/admin/games.json"
      expect(response.status).to eq(403)
    end

    it "refuses a normal user" do
      sign_in(user)
      get "/arcade/api/admin/games.json"
      expect(response.status).to eq(403)
    end

    it "refuses anonymous" do
      get "/arcade/api/admin/games.json"
      expect(response.status).to eq(403)
    end
  end

  describe "#update" do
    it "switches a game off and takes it out of the arcade listing" do
      sign_in(admin)
      put "/arcade/api/admin/games/#{on_game.id}.json", params: { enabled: false }

      expect(response.status).to eq(200)
      expect(response.parsed_body["game"]["enabled"]).to eq(false)
      expect(on_game.reload.enabled).to eq(false)
      expect(ArcadeGame.listed).not_to include(on_game)
    end

    it "switches one back on" do
      sign_in(admin)
      put "/arcade/api/admin/games/#{off_game.id}.json", params: { enabled: true }

      expect(response.status).to eq(200)
      expect(off_game.reload.enabled).to eq(true)
    end

    it "keeps every score, so switching back on restores the leaderboard" do
      run = ArcadeRun.issue!(user, on_game)
      ArcadeScore.create!(
        user_id: user.id,
        arcade_game_id: on_game.id,
        arcade_run_id: run.id,
        score: 500,
      )

      sign_in(admin)
      put "/arcade/api/admin/games/#{on_game.id}.json", params: { enabled: false }
      put "/arcade/api/admin/games/#{on_game.id}.json", params: { enabled: true }

      expect(on_game.reload.leaderboard(limit: 10).map(&:score)).to eq([500])
    end

    it "drops the record holder's flair for a game that is switched off" do
      run = ArcadeRun.issue!(user, on_game)
      ArcadeScore.create!(
        user_id: user.id,
        arcade_game_id: on_game.id,
        arcade_run_id: run.id,
        score: 500,
      )
      ArcadeRecordHolders.clear!
      expect(ArcadeRecordHolders.for_user(user.id)).to eq(["Alpha"])

      sign_in(admin)
      put "/arcade/api/admin/games/#{on_game.id}.json", params: { enabled: false }

      # No explicit cache clear here: the after_commit on the model does it.
      expect(ArcadeRecordHolders.for_user(user.id)).to eq([])
    end

    it "refuses a moderator" do
      sign_in(moderator)
      put "/arcade/api/admin/games/#{on_game.id}.json", params: { enabled: false }

      expect(response.status).to eq(403)
      expect(on_game.reload.enabled).to eq(true)
    end
  end

  describe "a run already in progress" do
    # Switching a game off mid-run must not swallow the score of someone already
    # playing. It works because submission finds the game through the run token
    # rather than through the enabled listing.
    it "still accepts the score" do
      token = ArcadeRun.issue!(user, on_game).token
      on_game.update!(enabled: false)

      sign_in(user)
      post "/arcade/api/runs/#{token}.json", params: { score: 250 }

      expect(response.status).to eq(200)
      expect(response.parsed_body["score"]).to eq(250)
      expect(ArcadeScore.where(user_id: user.id).count).to eq(1)
    end

    it "does not let a new run start on it" do
      on_game.update!(enabled: false)

      sign_in(user)
      post "/arcade/api/games/#{on_game.slug}/runs.json"

      expect(response.status).to eq(404)
    end
  end
end
