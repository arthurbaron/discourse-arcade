import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";

export default class ArcadeSeasonController extends Controller {
  @tracked label = "";
  @tracked months = [];
  @tracked standings = [];
  @tracked points = [];
  @tracked minPlayers = 3;
  @tracked monthTop = 5;

  setup(model) {
    this.label = model.label;
    this.months = model.months || [];
    this.standings = model.standings || [];
    this.points = model.rules?.points || [];
    this.minPlayers = model.rules?.min_players || 3;
    this.monthTop = model.rules?.month_top || 5;
  }

  get hasStandings() {
    return this.standings.length > 0;
  }

  // Written out from the server's own numbers, so the explanation on the page
  // can never drift from the scoring that produced the table under it.
  get pointsLabel() {
    const pts = this.points.map(String);
    if (pts.length < 2) {
      return pts.join("");
    }
    return `${pts.slice(0, -1).join(", ")} and ${pts[pts.length - 1]}`;
  }

  get topCount() {
    return this.points.length;
  }

  // Finished months only, newest first: the most recent result is the one
  // people come looking for.
  get pastMonths() {
    return this.months
      .filter((month) => !month.current)
      .map((month) => ({
        ...month,
        hasTop: (month.top || []).length > 0,
      }))
      .reverse();
  }

  get monthsLabel() {
    return this.months
      .map((month) => {
        const name = month.label.split(" ")[0];
        const games =
          month.games_counted === 1 ? "1 game" : `${month.games_counted} games`;
        return month.current ? `${name} so far, ${games}` : `${name}, ${games}`;
      })
      .join(" · ");
  }
}
