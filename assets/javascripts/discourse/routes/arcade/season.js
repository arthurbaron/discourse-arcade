import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class ArcadeSeasonRoute extends DiscourseRoute {
  async model() {
    return await ajax("/arcade/api/season.json");
  }

  titleToken() {
    return "Arcade season";
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.setup(model);
  }
}
