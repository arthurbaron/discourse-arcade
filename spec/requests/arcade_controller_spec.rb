# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArcadeController do
  fab!(:player) { Fabricate(:user) }
  fab!(:rival) { Fabricate(:user) }
  fab!(:moderator) { Fabricate(:moderator) }

  # min_run_seconds 0 keeps the happy-path specs from having to backdate runs.
  let!(:game) do
    ArcadeGame.create!(
      slug: "testgame",
      name: "Test Game",
      entry_path: "testgame/index.html",
      score_direction: "high",
      score_unit: "points",
      max_plausible_score: 10_000,
      min_run_seconds: 0,
    )
  end

  before { SiteSetting.arcade_enabled = true }

  def start_run(as:)
    sign_in(as)
    post "/arcade/api/games/#{game.slug}/runs.json"
    expect(response.status).to eq(200)
    response.parsed_body["token"]
  end

  def submit(token, score)
    post "/arcade/api/runs/#{token}.json", params: { score: score }
  end

  describe "authentication" do
    it "refuses anonymous access to the game list" do
      get "/arcade/api/games.json"
      expect(response.status).to eq(403)
    end

    it "refuses anonymous run requests" do
      post "/arcade/api/games/#{game.slug}/runs.json"
      expect(response.status).to eq(403)
    end
  end

  describe "#index" do
    it "lists enabled games with your best and the record holder" do
      token = start_run(as: player)
      submit(token, 500)

      get "/arcade/api/games.json"
      expect(response.status).to eq(200)

      entry = response.parsed_body["games"].find { |g| g["slug"] == game.slug }
      expect(entry["your_best"]).to eq(500)
      expect(entry["record"]["username"]).to eq(player.username)
      expect(entry["record"]["score"]).to eq(500)
    end

    it "hides disabled games" do
      game.update!(enabled: false)
      sign_in(player)

      get "/arcade/api/games.json"
      expect(response.parsed_body["games"].map { |g| g["slug"] }).not_to include(game.slug)
    end
  end

  describe "#start_run" do
    it "issues a token" do
      expect(start_run(as: player)).to be_present
      expect(ArcadeRun.last.user_id).to eq(player.id)
    end

    it "404s on an unknown game" do
      sign_in(player)
      post "/arcade/api/games/nope/runs.json"
      expect(response.status).to eq(404)
    end
  end

  describe "#submit_score" do
    it "stores a score and reports it as a personal best" do
      token = start_run(as: player)
      submit(token, 1234)

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["score"]).to eq(1234)
      expect(body["is_personal_best"]).to eq(true)
      expect(body["your_rank"]).to eq(1)
      expect(ArcadeScore.count).to eq(1)
    end

    it "does not call a lower score a personal best" do
      first = start_run(as: player)
      submit(first, 900)

      second = start_run(as: player)
      submit(second, 400)

      body = response.parsed_body
      expect(body["is_personal_best"]).to eq(false)
      expect(body["your_best"]).to eq(900)
    end

    it "refuses a token that was already redeemed" do
      token = start_run(as: player)
      submit(token, 100)
      submit(token, 9_000)

      expect(response.status).to eq(422)
      expect(response.parsed_body["error"]).to match(/already has a score/)
      expect(ArcadeScore.count).to eq(1)
    end

    it "refuses someone else's token" do
      token = start_run(as: player)

      sign_in(rival)
      submit(token, 100)

      expect(response.status).to eq(422)
      expect(response.parsed_body["error"]).to match(/belongs to someone else/)
    end

    it "refuses an unknown token" do
      sign_in(player)
      submit("deadbeef", 100)

      expect(response.status).to eq(422)
      expect(response.parsed_body["error"]).to match(/Unknown run/)
    end

    it "refuses a score above the plausible ceiling" do
      token = start_run(as: player)
      submit(token, 10_001)

      expect(response.status).to eq(422)
      expect(response.parsed_body["error"]).to match(/plausible range/)
      expect(ArcadeScore.count).to eq(0)
    end

    it "refuses a negative score" do
      token = start_run(as: player)
      submit(token, -5)

      expect(response.status).to eq(422)
      expect(ArcadeScore.count).to eq(0)
    end

    it "refuses a non-numeric score" do
      token = start_run(as: player)
      submit(token, "9999; drop table")

      expect(response.status).to eq(422)
      expect(response.parsed_body["error"]).to match(/whole number/)
    end

    it "refuses a score that arrived faster than the game allows" do
      game.update!(min_run_seconds: 30)
      token = start_run(as: player)
      submit(token, 500)

      expect(response.status).to eq(422)
      expect(response.parsed_body["error"]).to match(/quicker than the game allows/)
    end

    # Several games end legitimately in about a second, and a run that scored
    # nothing has nothing to fake. Rejecting those threw real play away and
    # accused the player of forging it.
    it "accepts a scoreless run however quick it was" do
      game.update!(min_run_seconds: 30)
      token = start_run(as: player)
      submit(token, 0)

      expect(response.status).to eq(200)
      expect(response.parsed_body["score"]).to eq(0)
      expect(ArcadeScore.count).to eq(1)
    end

    it "refuses an expired token" do
      token = start_run(as: player)
      ArcadeRun.find_by(token: token).update!(created_at: 4.hours.ago)
      submit(token, 500)

      expect(response.status).to eq(422)
      expect(response.parsed_body["error"]).to match(/expired/)
    end
  end

  describe "#show" do
    it "ranks one row per player, best score first" do
      # player scores twice, so only their best may appear
      submit(start_run(as: player), 300)
      submit(start_run(as: player), 800)
      submit(start_run(as: rival), 500)

      sign_in(player)
      get "/arcade/api/games/#{game.slug}.json"

      body = response.parsed_body
      rows = body["leaderboard"]

      expect(rows.length).to eq(2)
      expect(rows.map { |r| r["score"] }).to eq([800, 500])
      expect(rows.map { |r| r["username"] }).to eq([player.username, rival.username])
      expect(rows.first["rank"]).to eq(1)
      expect(body["your_best"]).to eq(800)
      expect(body["your_rank"]).to eq(1)
    end

    it "ranks ascending for a low-score-wins game" do
      game.update!(score_direction: "low")
      submit(start_run(as: player), 90)
      submit(start_run(as: rival), 30)

      sign_in(player)
      get "/arcade/api/games/#{game.slug}.json"

      body = response.parsed_body
      expect(body["leaderboard"].map { |r| r["score"] }).to eq([30, 90])
      expect(body["your_rank"]).to eq(2)
    end
  end

  describe "#destroy_score" do
    it "lets staff remove a score and drops it off the board" do
      submit(start_run(as: player), 800)
      score_id = ArcadeScore.last.id

      sign_in(moderator)
      delete "/arcade/api/scores/#{score_id}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["leaderboard"]).to eq([])
      expect(ArcadeScore.find(score_id).rejected).to eq(true)
    end

    it "refuses a normal user" do
      submit(start_run(as: player), 800)
      score_id = ArcadeScore.last.id

      sign_in(rival)
      delete "/arcade/api/scores/#{score_id}.json"

      expect(response.status).to eq(403)
      expect(ArcadeScore.find(score_id).rejected).to eq(false)
    end
  end

  describe "when the plugin is disabled" do
    it "404s" do
      SiteSetting.arcade_enabled = false
      sign_in(player)

      get "/arcade/api/games.json"
      expect(response.status).to eq(404)
    end
  end
end
