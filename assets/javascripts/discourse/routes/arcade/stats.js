import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class ArcadeStatsRoute extends DiscourseRoute {
  @service currentUser;
  @service router;

  // Nothing here is secret, but a member landing on a half-rendered admin page
  // is a bug either way, so a non-admin goes back to the arcade before the
  // request is made. The request would 403 regardless.
  beforeModel() {
    if (!this.currentUser?.admin) {
      this.router.replaceWith("arcade.index");
    }
  }

  async model() {
    return await ajax("/arcade/api/admin/stats.json");
  }

  titleToken() {
    return "Arcade statistics";
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.setup(model);
  }
}
