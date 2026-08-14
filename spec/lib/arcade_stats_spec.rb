# frozen_string_literal: true

# The stats page is arithmetic over rows that already existed, which means every
# way it can be wrong is silent: a wrong day boundary, a mean where a median was
# meant, counting a pulled score, or counting plays where players were meant.
# None of those make the page fail to load, so none of them would ever be
# noticed. Hence walking the numbers directly rather than checking the page
# renders.

require "rails_helper"

RSpec.describe ArcadeStats do
  fab!(:alice) { Fabricate(:user) }
  fab!(:bob) { Fabricate(:user) }

  fab!(:high_game) do
    ArcadeGame.create!(
      slug: "high",
      name: "High Game",
      entry_path: "high/index.html",
      score_direction: "high",
      score_unit: "points",
      position: 1,
    )
  end

  fab!(:low_game) do
    ArcadeGame.create!(
      slug: "low",
      name: "Low Game",
      entry_path: "low/index.html",
      score_direction: "low",
      score_unit: "seconds",
      position: 2,
    )
  end

  # A fixed zone on both sides, so "today" means the same thing to the spec and
  # to the service. Amsterdam is UTC+1 or +2, which is what makes the late
  # evening cases below actually test something.
  let(:zone) { "Europe/Amsterdam" }

  before { alice.user_option.update!(timezone: zone) }

  def add_score(user, game, score, at:, duration: 30, rejected: false)
    run = ArcadeRun.create!(user_id: user.id, arcade_game_id: game.id, token: SecureRandom.hex(16))
    ArcadeScore.create!(
      user_id: user.id,
      arcade_game_id: game.id,
      arcade_run_id: run.id,
      score: score,
      duration_seconds: duration,
      rejected: rejected,
      created_at: at,
    )
  end

  def local_now
    ActiveSupport::TimeZone[zone].now
  end

  def stats
    described_class.call(viewer: alice)
  end

  describe "totals" do
    it "counts today, the week and all time, and does not count pulled scores" do
      add_score(alice, high_game, 10, at: local_now.beginning_of_day + 1.hour)
      add_score(bob, high_game, 20, at: local_now.beginning_of_day + 2.hours)
      add_score(alice, high_game, 30, at: local_now - 3.days)
      add_score(alice, high_game, 40, at: local_now - 30.days)

      # Rejected today: a moderator pulled it, so it is not a play any more.
      add_score(bob, high_game, 999, at: local_now.beginning_of_day + 3.hours, rejected: true)

      result = stats[:totals]
      expect(result[:plays_today]).to eq(2)
      expect(result[:plays_week]).to eq(3)
      expect(result[:plays_total]).to eq(4)
    end

    it "counts distinct players, not plays" do
      4.times { |i| add_score(alice, high_game, i, at: local_now - 1.hour) }
      add_score(bob, high_game, 99, at: local_now - 1.hour)

      result = stats[:totals]
      expect(result[:plays_week]).to eq(5)
      expect(result[:players_week]).to eq(2)
    end

    # The bug this guards against is invisible: bucketing in UTC puts a game
    # played at half past midnight Amsterdam time on yesterday, so the number
    # Arthur checks in the morning quietly disagrees with what he played.
    it "uses the viewer's midnight, not the server's" do
      just_after_local_midnight = local_now.beginning_of_day + 30.minutes
      add_score(alice, high_game, 10, at: just_after_local_midnight)

      expect(stats[:totals][:plays_today]).to eq(1)
    end
  end

  describe "per game" do
    it "lists every game, including one nobody has played" do
      add_score(alice, high_game, 10, at: local_now - 1.hour)

      rows = stats[:games]
      expect(rows.map { |r| r[:slug] }).to eq(%w[high low])

      untouched = rows.find { |r| r[:slug] == "low" }
      expect(untouched[:plays_total]).to eq(0)
      expect(untouched[:players_total]).to eq(0)
      expect(untouched[:median_seconds]).to be_nil
      expect(untouched[:best_score]).to be_nil
      expect(untouched[:last_played_at]).to be_nil
    end

    it "reports a median duration, so one abandoned tab cannot skew it" do
      [10, 20, 30].each { |d| add_score(alice, high_game, 1, at: local_now - 1.hour, duration: d) }
      # A run left open for two hours. The mean would be over half an hour.
      add_score(bob, high_game, 1, at: local_now - 1.hour, duration: 7200)

      row = stats[:games].find { |r| r[:slug] == "high" }
      expect(row[:median_seconds]).to eq(25)
    end

    it "takes the best score in each game's own direction" do
      add_score(alice, high_game, 10, at: local_now - 1.hour)
      add_score(bob, high_game, 90, at: local_now - 1.hour)
      add_score(alice, low_game, 12, at: local_now - 1.hour)
      add_score(bob, low_game, 40, at: local_now - 1.hour)

      rows = stats[:games].index_by { |r| r[:slug] }
      expect(rows["high"][:best_score]).to eq(90)
      # Lower wins here, so the best is the smallest.
      expect(rows["low"][:best_score]).to eq(12)
    end

    it "separates the week from all time" do
      add_score(alice, high_game, 1, at: local_now - 2.days)
      add_score(alice, high_game, 2, at: local_now - 20.days)

      row = stats[:games].find { |r| r[:slug] == "high" }
      expect(row[:plays_week]).to eq(1)
      expect(row[:plays_total]).to eq(2)
    end
  end

  describe "trophies" do
    it "ranks holders by how many records they hold" do
      # Alice tops both games, Bob neither.
      add_score(alice, high_game, 100, at: local_now - 1.hour)
      add_score(bob, high_game, 10, at: local_now - 1.hour)
      add_score(alice, low_game, 5, at: local_now - 1.hour)
      add_score(bob, low_game, 50, at: local_now - 1.hour)
      ArcadeRecordHolders.clear!

      leaders = stats[:trophies]
      expect(leaders.first[:username]).to eq(alice.username)
      expect(leaders.first[:count]).to eq(2)
      expect(leaders.first[:games]).to eq(["High Game", "Low Game"])
      expect(leaders.map { |l| l[:username] }).not_to include(bob.username)
    end

    it "is empty when nothing has been played" do
      ArcadeRecordHolders.clear!
      expect(stats[:trophies]).to eq([])
    end
  end

  describe "trends" do
    it "returns an unbroken run of days, zeros included" do
      add_score(alice, high_game, 1, at: local_now.beginning_of_day - 2.days + 4.hours)

      days = stats[:by_day]
      expect(days.length).to eq(described_class::TREND_DAYS)

      # Chronological, no gaps, and the last entry is today.
      dates = days.map { |d| Date.parse(d[:date]) }
      expect(dates.each_cons(2).all? { |a, b| b == a + 1 }).to eq(true)
      expect(dates.last).to eq(local_now.to_date)

      # The one play landed on its own day and every other day reads zero,
      # which is the point of filling the gaps in.
      expect(days.count { |d| d[:count] == 1 }).to eq(1)
      expect(days.count { |d| d[:count].zero? }).to eq(described_class::TREND_DAYS - 1)
    end

    it "always returns seven weekdays, Monday first" do
      week = stats[:by_weekday]
      expect(week.map { |d| d[:name] }).to eq(
        %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday],
      )
      expect(week.map { |d| d[:count] }).to all(eq(0))
    end

    it "counts a play on the weekday it happened in the viewer's zone" do
      # Half past midnight on a Saturday in Amsterdam is still Friday in UTC.
      saturday = ActiveSupport::TimeZone[zone].parse("2026-08-15 00:30")
      add_score(alice, high_game, 1, at: saturday)

      week = stats[:by_weekday].index_by { |d| d[:name] }
      expect(week["Saturday"][:count]).to eq(1)
      expect(week["Friday"][:count]).to eq(0)
    end
  end

  describe "the viewer's timezone" do
    it "falls back to a usable zone when the viewer has none recorded" do
      bob.user_option.update!(timezone: nil)
      expect(described_class.call(viewer: bob)[:timezone]).to be_present
    end
  end
end
