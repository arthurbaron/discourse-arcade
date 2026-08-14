import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { service } from "@ember/service";

export default class ArcadeIndexController extends Controller {
  @service currentUser;

  @tracked games = [];

  setup(model) {
    this.games = model.games || [];
  }

  get hasGames() {
    return this.games.length > 0;
  }

  // The stats screen is admin only. This hides the way in; the route turns a
  // non-admin around and the API refuses them, so this is convenience and not
  // the guard.
  get isAdmin() {
    return this.currentUser?.admin ?? false;
  }
}
