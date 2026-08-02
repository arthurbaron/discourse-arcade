import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";

export default class ArcadeIndexController extends Controller {
  @tracked games = [];

  setup(model) {
    this.games = model.games || [];
  }

  get hasGames() {
    return this.games.length > 0;
  }
}
