# frozen_string_literal: true

# The arcade's calendar. Leaderboards run per calendar month and reset on the
# 1st, and the months add up to a season that follows the football season,
# August to July, the same rhythm the rest of the forum lives by.
#
# A reset is a filter, never a deletion. Every score keeps its date and stays in
# the table, so "this month" is just a window over it. That is what makes the
# season standings possible at all, keeps the all-time records alive, and means
# nothing about a month rolling over is irreversible.
#
# Every boundary sits in one fixed zone. A leaderboard is the same list for
# everyone reading it, so where a month starts cannot depend on who is looking.
# That is deliberately the opposite of the stats screen, which buckets days in
# the viewer's own zone because there the question is "how busy was my evening".
class ArcadePeriod
  ZONE = "Europe/Amsterdam"
  SEASON_START_MONTH = 8

  def self.zone
    ActiveSupport::TimeZone[ZONE]
  end

  # A month is identified by its first day, as a Date.
  def self.month_of(time)
    time.in_time_zone(zone).to_date.beginning_of_month
  end

  def self.current_month
    month_of(Time.zone.now)
  end

  def self.previous_month
    current_month.prev_month
  end

  # The instants a month covers, half-open. Built in the zone rather than by
  # adding 30 days, so a month that crosses a clock change is still exactly
  # midnight to midnight.
  def self.range(month)
    start = zone.local(month.year, month.month, 1)
    start...zone.local(month.next_month.year, month.next_month.month, 1)
  end

  def self.current_range
    range(current_month)
  end

  # Named by the year it starts: August 2026 to July 2027 is season 2026.
  def self.season_of(month)
    month.month >= SEASON_START_MONTH ? month.year : month.year - 1
  end

  def self.current_season
    season_of(current_month)
  end

  # The months of a season that have started, oldest first. A season in the
  # future has none and a finished one has all twelve.
  def self.months_of(season, upto: current_month)
    first = Date.new(season, SEASON_START_MONTH, 1)
    last = [first.advance(months: 11), upto].min

    months = []
    month = first
    while month <= last
      months << month
      month = month.next_month
    end
    months
  end

  def self.season_range(season)
    first = Date.new(season, SEASON_START_MONTH, 1)
    range(first).begin...range(first.advance(months: 11)).end
  end

  def self.key(month)
    month.strftime("%Y-%m")
  end

  def self.label(month)
    month.strftime("%B %Y")
  end

  def self.season_label(season)
    "#{season}/#{(season + 1).to_s[-2..]}"
  end
end
