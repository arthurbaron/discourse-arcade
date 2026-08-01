# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArcadeRecordHolders do
  fab!(:leader) { Fabricate(:user) }
  fab!(:runner_up) { Fabricate(:user) }

  def make_game(slug, name, direction: "high", enabled: true, position: 1)
    ArcadeGame.create!(
      slug: slug,
      name: name,
      entry_path: "#{slug}/index.html",
      score_direction: direction,
      max_plausible_score: 10_000,
      min_run_seconds: 0,
      enabled: enabled,
      position: position,
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

  before { described_class.clear! }

  it "is empty when nothing has been played" do
    make_game("a", "Game A")
    expect(described_class.map).to eq({})
  end

  it "names the game its leader holds" do
    game = make_game("a", "Game A")
    record_score(leader, game, 500)
    described_class.clear!

    expect(described_class.for_user(leader.id)).to eq(["Game A"])
  end

  it "credits only first place" do
    game = make_game("a", "Game A")
    record_score(leader, game, 500)
    record_score(runner_up, game, 300)
    described_class.clear!

    expect(described_class.for_user(leader.id)).to eq(["Game A"])
    expect(described_class.for_user(runner_up.id)).to eq([])
  end

  it "collects every game one person leads" do
    first = make_game("a", "Game A", position: 1)
    second = make_game("b", "Game B", position: 2)
    record_score(leader, first, 500)
    record_score(leader, second, 700)
    described_class.clear!

    expect(described_class.for_user(leader.id)).to contain_exactly("Game A", "Game B")
  end

  it "ignores a removed score" do
    game = make_game("a", "Game A")
    record_score(leader, game, 500)
    record_score(runner_up, game, 300)
    ArcadeScore.find_by(user_id: leader.id).update!(rejected: true)
    described_class.clear!

    expect(described_class.for_user(leader.id)).to eq([])
    expect(described_class.for_user(runner_up.id)).to eq(["Game A"])
  end

  it "ignores a disabled game" do
    game = make_game("a", "Game A", enabled: false)
    record_score(leader, game, 500)
    described_class.clear!

    expect(described_class.map).to eq({})
  end

  it "follows a game where a lower score wins" do
    game = make_game("a", "Time Trial", direction: "low")
    record_score(leader, game, 30)
    record_score(runner_up, game, 90)
    described_class.clear!

    expect(described_class.for_user(leader.id)).to eq(["Time Trial"])
    expect(described_class.for_user(runner_up.id)).to eq([])
  end

  it "handles a nil user id" do
    expect(described_class.for_user(nil)).to eq([])
  end

  describe "cache invalidation" do
    it "picks up a new leader once a score is submitted through the service" do
      game = make_game("a", "Game A")
      record_score(runner_up, game, 100)
      expect(described_class.for_user(runner_up.id)).to eq(["Game A"])

      run = ArcadeRun.issue!(leader, game)
      result = ArcadeScoreSubmission.call(user: leader, token: run.token, raw_score: 900)
      expect(result.ok?).to eq(true)

      expect(described_class.for_user(leader.id)).to eq(["Game A"])
      expect(described_class.for_user(runner_up.id)).to eq([])
    end

    it "picks up a game being disabled" do
      game = make_game("a", "Game A")
      record_score(leader, game, 500)
      expect(described_class.for_user(leader.id)).to eq(["Game A"])

      game.update!(enabled: false)

      expect(described_class.for_user(leader.id)).to eq([])
    end
  end
end
