import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
// The 3.2-era checkout at ~/discourse runs ember-source 3.28, whose
// @ember/service exports only `inject`, so this file cannot load there. That is
// deliberate: current Discourse raises the old `inject as service` import as an
// error in its test environment, and it surfaced as a suite that went red or
// green depending on the random spec order. Production runs current Discourse,
// and ~/discourse-next is the reference now.
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class ArcadeGameController extends Controller {
  @service dialog;

  @tracked game = null;
  @tracked leaderboard = [];
  @tracked yourBest = null;
  @tracked yourRank = null;
  @tracked canModerate = false;
  @tracked period = null;
  @tracked allTimeRecord = null;
  @tracked lastMonthWinner = null;

  setup(model) {
    this.game = model.game;
    this.leaderboard = model.leaderboard || [];
    this.yourBest = model.your_best;
    this.yourRank = model.your_rank;
    this.canModerate = model.can_moderate || false;
    this.period = model.period || null;
    this.allTimeRecord = model.all_time_record || null;
    this.lastMonthWinner = model.last_month_winner || null;
  }

  get recordToBeat() {
    return this.leaderboard[0] || null;
  }

  // Only shown when it adds something. If this month's leader holds it, or
  // the board is empty and last month's winner (already named above) holds it,
  // the line would repeat the sentence right before it.
  get showAllTimeRecord() {
    const record = this.allTimeRecord;
    if (!record) {
      return false;
    }
    if (record.id === this.recordToBeat?.id) {
      return false;
    }
    if (!this.hasScores && record.id === this.lastMonthWinner?.id) {
      return false;
    }
    return true;
  }

  get hasScores() {
    return this.leaderboard.length > 0;
  }

  // Called by the game frame once the server has accepted a score.
  @action
  scoreSaved(payload) {
    this.leaderboard = payload.leaderboard || this.leaderboard;
    this.yourBest = payload.your_best;
    this.yourRank = payload.your_rank;
    if (payload.all_time_record !== undefined) {
      this.allTimeRecord = payload.all_time_record;
    }

    // Replaced rather than mutated, so the template picks the new count up.
    if (payload.plays_count !== undefined) {
      this.game = { ...this.game, plays_count: payload.plays_count };
    }
  }

  @action
  removeScore(entry) {
    this.dialog.yesNoConfirm({
      message: `Remove ${entry.username}'s score of ${entry.score}?`,
      didConfirm: async () => {
        try {
          const payload = await ajax(`/arcade/api/scores/${entry.id}.json`, {
            type: "DELETE",
          });
          this.leaderboard = payload.leaderboard || [];
        } catch (e) {
          popupAjaxError(e);
        }
      },
    });
  }
}
