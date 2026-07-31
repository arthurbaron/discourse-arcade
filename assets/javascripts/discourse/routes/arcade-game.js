import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class ArcadeGameRoute extends DiscourseRoute {
  async model(params) {
    return await ajax(`/arcade/api/games/${params.slug}.json`);
  }

  titleToken() {
    return this.currentModel?.game?.name || "Arcade";
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.setup(model);
  }
}
