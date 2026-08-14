import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { trustHTML } from "@ember/template";

// Bars are drawn as a share of the busiest entry in their own series, so a quiet
// fortnight still reads as a shape rather than as fourteen slivers. A series
// where nothing has been played has no busiest entry, hence the guard: without
// it every bar would be NaN% tall.
//
// The height arrives as a ready-made style rather than a number the template
// interpolates, because a bar height is the one genuinely dynamic dimension here
// and building it in the template is what the style-concatenation rule exists to
// stop.
function withHeights(entries) {
  const max = Math.max(...entries.map((e) => e.count), 0);

  return entries.map((entry) => {
    const height = max > 0 ? Math.round((entry.count / max) * 100) : 0;

    return {
      ...entry,
      height,
      style: trustHTML(`height: ${height}%`),
      isPeak: max > 0 && entry.count === max,
    };
  });
}

function formatDuration(seconds) {
  if (seconds === null || seconds === undefined) {
    return "-";
  }
  if (seconds < 60) {
    return `${seconds}s`;
  }

  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  return `${minutes}m ${String(rest).padStart(2, "0")}s`;
}

// "Last played" is only ever read as a rough sense of whether a game is still
// alive, so recent days are worth more than precision and anything older than a
// month is better off as a date.
function formatLastPlayed(iso) {
  if (!iso) {
    return "never";
  }

  const then = new Date(iso);
  const midnight = new Date();
  midnight.setHours(0, 0, 0, 0);

  const days = Math.floor((midnight - then) / 86400000) + 1;

  if (days <= 0) {
    return "today";
  }
  if (days === 1) {
    return "yesterday";
  }
  if (days < 30) {
    return `${days} days ago`;
  }

  return then.toLocaleDateString();
}

export default class ArcadeStatsController extends Controller {
  @tracked totals = {};
  @tracked games = [];
  @tracked trophies = [];
  @tracked byDay = [];
  @tracked byWeekday = [];
  @tracked timezone = null;

  setup(model) {
    this.totals = model.totals || {};
    this.timezone = model.timezone;

    // Joined here rather than in the template, where an array renders as its own
    // comma-separated toString and looks right by accident until a name
    // contains a comma.
    this.trophies = (model.trophies || []).map((holder) => ({
      ...holder,
      gamesLabel: (holder.games || []).join(", "),
    }));

    this.games = (model.games || []).map((game) => ({
      ...game,
      medianLabel: formatDuration(game.median_seconds),
      lastPlayedLabel: formatLastPlayed(game.last_played_at),
    }));

    this.byDay = withHeights(model.by_day || []).map((day) => ({
      ...day,
      // Day of the month is enough on a fortnight's axis, and it keeps the
      // labels narrow enough to fit on a phone.
      label: new Date(day.date).getDate(),
    }));

    this.byWeekday = withHeights(model.by_weekday || []).map((day) => ({
      ...day,
      short: day.name.slice(0, 3),
    }));
  }

  get hasPlays() {
    return (this.totals.plays_total || 0) > 0;
  }

  get busiestWeekday() {
    return this.byWeekday.find((day) => day.isPeak)?.name;
  }
}
