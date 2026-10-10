# frozen_string_literal: true

# The season table is the reason people keep coming back after a month resets,
# so its arithmetic has to be beyond argument. It scores placings rather than
# raw points, because the games score on scales thousands of times apart and a
# raw total would just be the Intercept board with extra steps.

require "rails_helper"

RSpec.describe ArcadeSeason do
  fab!(:ann) { Fabricate(:user, username: "ann") }
  fab!(:bob) { Fabricate(:user, username: "bob") }
  fab!(:cas) { Fabricate(:user, username: "cas") }
  fab!(:dee) { Fabricate(:user, username: "dee") }
  fab!(:eve) { Fabricate(:user, username: "eve") }
  fab!(:fay) { Fabricate(:user, username: "fay") }

  # Mid October 2026, so August, September and October are the season so far.
  before do
    freeze_time Time.utc(2026, 10, 15, 12, 0)
    Discourse.cache.clear
  end

  def make_game(slug, direction: "high", enabled: true, position: 1)
    ArcadeGame.create!(
      slug: slug,
      name: slug.capitalize,
      entry_path: "#{slug}/index.html",
      score_direction: direction,
      max_plausible_score: 1_000_000,
      min_run_seconds: 0,
      enabled: enabled,
      position: position,
    )
  end

  def score(user, game, value, at:, rejected: false)
    run = ArcadeRun.issue!(user, game)
    ArcadeScore.create!(
      user_id: user.id,
      arcade_game_id: game.id,
      arcade_run_id: run.id,
      score: value,
      rejected: rejected,
      created_at: at,
    )
  end

  def table
    described_class.standings(2026)
  end

  def points_for(user)
    table[:standings].find { |row| row[:user_id] == user.id }&.dig(:points)
  end

  let(:in_august) { Time.utc(2026, 8, 10, 12, 0) }
  let(:in_september) { Time.utc(2026, 9, 10, 12, 0) }
  let(:in_october) { Time.utc(2026, 10, 10, 12, 0) }

  it "pays 10, 7, 5, 3 and 1 to the top five, and nothing to sixth" do
    game = make_game("snake")
    [[ann, 60], [bob, 50], [cas, 40], [dee, 30], [eve, 20], [fay, 10]].each do |user, value|
      score(user, game, value, at: in_october)
    end

    expect([ann, bob, cas, dee, eve].map { |u| points_for(u) }).to eq([10, 7, 5, 3, 1])
    expect(points_for(fay)).to be_nil
  end

  # A podium needs three people. Without this, whoever opened a quiet game once
  # would take ten points for turning up.
  it "pays nothing for a game fewer than three people played that month" do
    game = make_game("snake")
    score(ann, game, 60, at: in_october)
    score(bob, game, 50, at: in_october)

    expect(table[:standings]).to eq([])
    expect(table[:months].last[:games_counted]).to eq(0)
  end

  it "counts each player once per month, however many runs they played" do
    game = make_game("snake")
    5.times { |i| score(ann, game, 10 + i, at: in_october) }
    score(bob, game, 5, at: in_october)

    # Two people, many runs: still not a podium.
    expect(table[:standings]).to eq([])
  end

  it "adds up across games and across months" do
    snake = make_game("snake", position: 1)
    stack = make_game("stack", position: 2)

    # August, snake: ann wins.
    score(ann, snake, 30, at: in_august)
    score(bob, snake, 20, at: in_august)
    score(cas, snake, 10, at: in_august)

    # September, stack: bob wins, ann third.
    score(bob, stack, 30, at: in_september)
    score(cas, stack, 20, at: in_september)
    score(ann, stack, 10, at: in_september)

    expect(points_for(ann)).to eq(10 + 5)
    expect(points_for(bob)).to eq(7 + 10)
    expect(points_for(cas)).to eq(5 + 7)

    bob_row = table[:standings].find { |row| row[:user_id] == bob.id }
    expect(bob_row[:wins]).to eq(1)
    expect(bob_row[:podiums]).to eq(2)
    expect(table[:standings].first[:user_id]).to eq(bob.id)
  end

  it "judges each month on its own, so last month's score does not carry over" do
    game = make_game("snake")
    # ann's huge August score must not help her in October.
    score(ann, game, 9_999, at: in_august)
    score(bob, game, 1, at: in_august)
    score(cas, game, 1, at: in_august)

    score(bob, game, 30, at: in_october)
    score(cas, game, 20, at: in_october)
    score(ann, game, 10, at: in_october)

    expect(points_for(ann)).to eq(10 + 5)
  end

  it "ranks a lower-is-better game the right way round" do
    game = make_game("sprint", direction: "low")
    score(ann, game, 12, at: in_october)
    score(bob, game, 30, at: in_october)
    score(cas, game, 20, at: in_october)

    expect([ann, cas, bob].map { |u| points_for(u) }).to eq([10, 7, 5])
  end

  it "breaks a tied score the way the leaderboard does: first there wins" do
    game = make_game("snake")
    score(bob, game, 50, at: in_october)
    score(ann, game, 50, at: in_october + 1.hour)
    score(cas, game, 10, at: in_october)

    expect(points_for(bob)).to eq(10)
    expect(points_for(ann)).to eq(7)
  end

  # The season page and the monthly board must never disagree about who won.
  it "names the same winner as that month's leaderboard" do
    game = make_game("snake")
    score(cas, game, 70, at: in_september)
    score(ann, game, 70, at: in_september + 1.minute)
    score(bob, game, 40, at: in_september)

    month = ArcadePeriod.range(Date.new(2026, 9, 1))
    leader = game.leaderboard(limit: 1, within: month).first

    winner = table[:standings].max_by { |row| row[:wins] }
    expect(winner[:user_id]).to eq(leader.user_id)
  end

  it "ignores rejected scores" do
    game = make_game("snake")
    score(ann, game, 999, at: in_october, rejected: true)
    score(ann, game, 5, at: in_october)
    score(bob, game, 30, at: in_october)
    score(cas, game, 20, at: in_october)

    expect(points_for(ann)).to eq(5)
  end

  it "leaves out scores from before the season started" do
    game = make_game("snake")
    [ann, bob, cas].each { |user| score(user, game, 50, at: Time.utc(2026, 7, 20, 12, 0)) }

    expect(table[:standings]).to eq([])
  end

  # Points earned stay earned, so switching a game off never takes any away.
  it "keeps points from a game that has since been switched off" do
    game = make_game("snake", enabled: false)
    score(ann, game, 30, at: in_august)
    score(bob, game, 20, at: in_august)
    score(cas, game, 10, at: in_august)

    expect(points_for(ann)).to eq(10)
  end

  it "breaks a points tie on wins, and shares a rank only when everything is level" do
    snake = make_game("snake", position: 1)
    stack = make_game("stack", position: 2)

    # ann: one win (10). bob: 7 + 3 = 10 with no win.
    score(ann, snake, 30, at: in_october)
    score(bob, snake, 20, at: in_october)
    score(cas, snake, 10, at: in_october)

    score(dee, stack, 40, at: in_october)
    score(eve, stack, 30, at: in_october)
    score(fay, stack, 20, at: in_october)
    score(bob, stack, 10, at: in_october)

    rows = table[:standings]
    ann_row = rows.find { |r| r[:user_id] == ann.id }
    bob_row = rows.find { |r| r[:user_id] == bob.id }
    dee_row = rows.find { |r| r[:user_id] == dee.id }

    expect(ann_row[:points]).to eq(10)
    expect(bob_row[:points]).to eq(10)
    expect(ann_row[:rank]).to be < bob_row[:rank]

    # ann and dee: one win, ten points, one podium each. Level, so one rank.
    expect(dee_row[:rank]).to eq(ann_row[:rank])
  end

  it "reports the months so far, marking the one still in progress" do
    make_game("snake")
    months = table[:months]

    expect(months.map { |m| m[:key] }).to eq(%w[2026-08 2026-09 2026-10])
    expect(months.map { |m| m[:current] }).to eq([false, false, true])
    expect(table[:label]).to eq("2026/27")
    expect(table[:rules]).to eq(points: [10, 7, 5, 3, 1], min_players: 3, month_top: 5)
  end

  it "is recomputed once a new score clears the cache" do
    game = make_game("snake")
    [[ann, 30], [bob, 20]].each { |user, value| score(user, game, value, at: in_october) }
    expect(table[:standings]).to eq([])

    score(cas, game, 10, at: in_october)
    ArcadeRecordHolders.clear!

    expect(points_for(ann)).to eq(10)
  end

  describe "each month's top five" do
    def top(key)
      table[:months].find { |m| m[:key] == key }[:top]
    end

    it "gives each finished month its own top five, scored like the season" do
      snake = make_game("snake", position: 1)
      stack = make_game("stack", position: 2)

      # September: ann wins snake and is third in stack (15), bob 7 + 10 (17),
      # cas 5 + 7 (12), dee only plays stack and comes last (3).
      score(ann, snake, 30, at: in_september)
      score(bob, snake, 20, at: in_september)
      score(cas, snake, 10, at: in_september)
      score(bob, stack, 40, at: in_september)
      score(cas, stack, 30, at: in_september)
      score(ann, stack, 20, at: in_september)
      score(dee, stack, 10, at: in_september)

      rows = top("2026-09")
      expect(rows.map { |r| [r[:user_id], r[:points], r[:rank]] }).to eq(
        [[bob.id, 17, 1], [ann.id, 15, 2], [cas.id, 12, 3], [dee.id, 3, 4]],
      )
    end

    # A month is judged on its own: August's points do not leak into September's
    # list, even though both feed the same season total.
    it "keeps each month separate from the others" do
      game = make_game("snake")
      score(ann, game, 30, at: in_august)
      score(bob, game, 20, at: in_august)
      score(cas, game, 10, at: in_august)

      score(dee, game, 30, at: in_september)
      score(eve, game, 20, at: in_september)
      score(fay, game, 10, at: in_september)

      expect(top("2026-08").map { |r| r[:user_id] }).to eq([ann.id, bob.id, cas.id])
      expect(top("2026-09").map { |r| r[:user_id] }).to eq([dee.id, eve.id, fay.id])
    end

    it "keeps a shared fifth place rather than picking one of them" do
      snake = make_game("snake", position: 1)
      stack = make_game("stack", position: 2)

      # snake: ann 10, bob 7, cas 5. stack: dee 10, eve 7, fay 5.
      # Level pairs on everything: ann & dee, bob & eve, cas & fay.
      [[ann, 30], [bob, 20], [cas, 10]].each { |u, v| score(u, snake, v, at: in_september) }
      [[dee, 30], [eve, 20], [fay, 10]].each { |u, v| score(u, stack, v, at: in_september) }

      # Six players on five places: the last two are level, so both stay.
      rows = top("2026-09")
      expect(rows.map { |r| r[:rank] }).to eq([1, 1, 3, 3, 5, 5])
      expect(rows.map { |r| r[:user_id] }).to contain_exactly(ann.id, dee.id, bob.id, eve.id, cas.id, fay.id)
    end

    # The month in progress is the live table already, and a result that can
    # still change is not a result.
    it "has no list for the month still in progress" do
      game = make_game("snake")
      [[ann, 30], [bob, 20], [cas, 10]].each { |u, v| score(u, game, v, at: in_october) }

      expect(top("2026-10")).to eq([])
      expect(points_for(ann)).to eq(10)
    end

    it "is empty for a month where no game reached three players" do
      game = make_game("snake")
      score(ann, game, 30, at: in_august)
      score(bob, game, 20, at: in_august)

      expect(top("2026-08")).to eq([])
    end
  end

  # Found in development: a table cached by the previous code lacked the
  # per-month list, and the season endpoint crashed on it until it expired.
  it "never reads a table cached under an older shape" do
    stale = "arcade_season:2026:#{ArcadePeriod.key(ArcadePeriod.current_month)}"
    Discourse.cache.write(stale, { months: [{ key: "2026-08" }] })

    expect(described_class.cache_key(2026)).not_to eq(stale)
    expect(table[:months].first).to have_key(:top)
  end
end
