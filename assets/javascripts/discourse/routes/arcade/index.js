import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class ArcadeIndexRoute extends DiscourseRoute {
  async model() {
    const data = await ajax("/arcade/api/games.json");
    return { games: data.games || [] };
  }

  titleToken() {
    return "Arcade";
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.setup(model);
  }
}
