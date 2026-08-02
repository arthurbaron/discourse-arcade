import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DToggleSwitch from "discourse/ui-kit/d-toggle-switch";
import { i18n } from "discourse-i18n";

// Switching a game off takes it off /arcade and removes its record holder's
// trophy from every post, because both read the same enabled column. Scores are
// kept, so switching it back on restores the leaderboard exactly as it was, and
// anyone already mid-run can still finish and have their score counted.
export default class ArcadeGameToggles extends Component {
  @tracked games = [];
  @tracked loading = true;
  // Which rows are waiting on the server, so a double click cannot race itself.
  @tracked pending = new Set();

  constructor() {
    super(...arguments);
    this.load();
  }

  async load() {
    try {
      const data = await ajax("/arcade/api/admin/games.json");
      this.games = data.games || [];
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.loading = false;
    }
  }

  // Not bound into the template: calling a plain method with an argument from a
  // curly expression is not a valid helper invocation, and it threw mid-render,
  // truncating the list after the first row. The guard in toggle() is what
  // actually prevents a double click racing itself.
  isPending(game) {
    return this.pending.has(game.id);
  }

  @action
  async toggle(game) {
    if (this.isPending(game)) {
      return;
    }

    this.pending = new Set([...this.pending, game.id]);

    try {
      const data = await ajax(`/arcade/api/admin/games/${game.id}.json`, {
        type: "PUT",
        data: { enabled: !game.enabled },
      });

      // Replace the row from the server's answer rather than assuming the flip
      // worked, so the switch can never disagree with the database.
      this.games = this.games.map((row) =>
        row.id === data.game.id ? data.game : row
      );
    } catch (e) {
      popupAjaxError(e);
    } finally {
      const next = new Set(this.pending);
      next.delete(game.id);
      this.pending = next;
    }
  }

  <template>
    <div class="arcade-admin-games">
      {{#if this.loading}}
        <p class="arcade-admin-games__loading">{{i18n "loading"}}</p>
      {{else}}
        <ul class="arcade-admin-games__list">
          {{#each this.games as |game|}}
            <li
              class="arcade-admin-games__row
                {{unless game.enabled 'arcade-admin-games__row--off'}}"
            >
              <div class="arcade-admin-games__art">
                {{#if game.thumbnail_url}}
                  <img src={{game.thumbnail_url}} alt="" width="72" height="41" />
                {{/if}}
              </div>

              <div class="arcade-admin-games__text">
                <h3 class="arcade-admin-games__name">{{game.name}}</h3>
                {{#if game.tagline}}
                  <p class="arcade-admin-games__tagline">{{game.tagline}}</p>
                {{/if}}
                <p class="arcade-admin-games__meta">
                  {{i18n
                    "arcade.admin.games.scores"
                    count=game.scores_count
                  }}
                </p>
              </div>

              <div class="arcade-admin-games__switch">
                <DToggleSwitch
                  @state={{game.enabled}}
                  {{on "click" (fn this.toggle game)}}
                />
              </div>
            </li>
          {{/each}}
        </ul>
      {{/if}}
    </div>
  </template>
}
