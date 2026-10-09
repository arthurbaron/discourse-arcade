# frozen_string_literal: true

# The calendar every leaderboard, trophy and season placing hangs off. A month
# boundary in the wrong zone moves a late-evening score into the wrong month,
# which silently changes who won it, so the edges are pinned here rather than
# trusted.

require "rails_helper"

RSpec.describe ArcadePeriod do
  describe "months" do
    it "puts a late October evening in Amsterdam in October, not November" do
      # 21:30 UTC on the 31st is 22:30 in Amsterdam, still October.
      expect(described_class.month_of(Time.utc(2026, 10, 31, 21, 30))).to eq(Date.new(2026, 10, 1))
    end

    it "puts just past midnight on the 1st in Amsterdam in the new month" do
      # 23:30 UTC on 31 October is 00:30 on 1 November in Amsterdam (CET).
      expect(described_class.month_of(Time.utc(2026, 10, 31, 23, 30))).to eq(Date.new(2026, 11, 1))
    end

    it "spans exactly midnight to midnight in Amsterdam, across a clock change" do
      # October 2026 contains the switch back from summer time.
      range = described_class.range(Date.new(2026, 10, 1))

      expect(range.begin).to eq(Time.utc(2026, 9, 30, 22, 0))
      expect(range.end).to eq(Time.utc(2026, 10, 31, 23, 0))
      expect(range.exclude_end?).to eq(true)
    end

    it "follows the clock" do
      freeze_time Time.utc(2026, 10, 9, 12, 0)

      expect(described_class.current_month).to eq(Date.new(2026, 10, 1))
      expect(described_class.previous_month).to eq(Date.new(2026, 9, 1))
      expect(described_class.label(described_class.current_month)).to eq("October 2026")
      expect(described_class.key(described_class.current_month)).to eq("2026-10")
    end
  end

  describe "seasons" do
    it "runs August to July, like the football season" do
      expect(described_class.season_of(Date.new(2026, 8, 1))).to eq(2026)
      expect(described_class.season_of(Date.new(2026, 12, 1))).to eq(2026)
      expect(described_class.season_of(Date.new(2027, 1, 1))).to eq(2026)
      expect(described_class.season_of(Date.new(2027, 7, 1))).to eq(2026)
      expect(described_class.season_of(Date.new(2027, 8, 1))).to eq(2027)

      expect(described_class.season_label(2026)).to eq("2026/27")
      expect(described_class.season_label(2099)).to eq("2099/00")
    end

    it "lists the months that have started, and no more" do
      months = described_class.months_of(2026, upto: Date.new(2026, 10, 1))
      expect(months).to eq([Date.new(2026, 8, 1), Date.new(2026, 9, 1), Date.new(2026, 10, 1)])

      expect(described_class.months_of(2026, upto: Date.new(2030, 1, 1)).length).to eq(12)
      expect(described_class.months_of(2027, upto: Date.new(2026, 10, 1))).to eq([])
    end
  end
end
