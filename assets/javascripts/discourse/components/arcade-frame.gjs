import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import icon from "discourse/ui-kit/helpers/d-icon";

// Colour scheme variables handed to the game through its URL. The frame is
// sandboxed, so a game cannot read the forum's CSS itself.
const THEME_VARS = {
  bg: "--secondary",
  fg: "--primary",
  accent: "--tertiary",
  muted: "--primary-medium",
  low: "--primary-low",
};

export default class ArcadeFrame extends Component {
  // idle | loading | playing | saving | done
  @tracked status = "idle";
  @tracked frameSrc = null;
  @tracked lastScore = null;
  @tracked isPersonalBest = false;
  @tracked error = null;

  _token = null;
  _runCount = 0;

  // A Glimmer component has no `this.element`, so the iframe hands itself over
  // when it renders. That is also more honest than reaching into the DOM: this
  // component only ever wants the one element it owns.
  _frame = null;

  constructor() {
    super(...arguments);
    this._messageHandler = (event) => this._onMessage(event);
    window.addEventListener("message", this._messageHandler);
  }

  // Glimmer's teardown hook, in place of willDestroyElement. Missing this
  // leaks a window listener per game page visited.
  willDestroy() {
    super.willDestroy(...arguments);
    window.removeEventListener("message", this._messageHandler);
  }

  get overlayVisible() {
    return this.status !== "playing";
  }

  @action
  registerFrame(element) {
    this._frame = element;
    // The iframe only renders once a run has started, so this is also the
    // moment to hand it the keyboard.
    element.focus();
  }

  @action
  async start() {
    this.error = null;
    this.status = "loading";

    try {
      const { token } = await ajax(
        `/arcade/api/games/${this.args.game.slug}/runs.json`,
        { type: "POST" }
      );

      this._token = token;
      this._runCount += 1;
      this.lastScore = null;
      this.isPersonalBest = false;
      this._frame = null;
      this.frameSrc = this._buildFrameSrc();
      this.status = "playing";
    } catch (e) {
      this.status = "idle";
      popupAjaxError(e);
    }
  }

  _buildFrameSrc() {
    const styles = getComputedStyle(document.documentElement);
    const params = new URLSearchParams();

    Object.keys(THEME_VARS).forEach((key) => {
      const value = styles.getPropertyValue(THEME_VARS[key]).trim();
      if (value) {
        params.set(key, value);
      }
    });

    // Changing the URL on every run guarantees a fresh document, so "play
    // again" really restarts the game.
    params.set("run", String(this._runCount));

    // Game files sit under /plugins/, which nginx serves as immutable for a
    // year. The version is a content hash from the server; the game's HTML
    // carries it onto its scripts, so a deploy reaches every cached device.
    if (this.args.game.assets_version) {
      params.set("v", this.args.game.assets_version);
    }

    return `${this.args.game.play_url}?${params.toString()}`;
  }

  _focusFrame() {
    this._frame?.focus();
  }

  // The frame is sandboxed without allow-same-origin, so its origin is opaque
  // and event.origin is useless. Comparing event.source against our own frame
  // is the reliable check.
  _onMessage(event) {
    if (!this._frame || event.source !== this._frame.contentWindow) {
      return;
    }

    const data = event.data;
    if (!data || typeof data !== "object") {
      return;
    }

    if (data.type === "arcade:ready") {
      this._focusFrame();
    } else if (data.type === "arcade:score") {
      this._submitScore(data.score);
    }
  }

  async _submitScore(rawScore) {
    // One score per run. A game that reports twice gets ignored the second time.
    if (!this._token) {
      return;
    }

    const token = this._token;
    this._token = null;
    this.status = "saving";

    try {
      const payload = await ajax(`/arcade/api/runs/${token}.json`, {
        type: "POST",
        data: { score: rawScore },
      });

      this.lastScore = payload.score;
      this.isPersonalBest = payload.is_personal_best;
      this.status = "done";
      this.args.onScore?.(payload);
    } catch (e) {
      this.error =
        e.jqXHR?.responseJSON?.error || "That score could not be saved.";
      this.status = "done";
    }
  }

  // The wrapper div is not decoration. A classic component brought its own
  // element and the caller put arcade-frame on it; a Glimmer component is
  // tagless, so without this div that class lands nowhere. It is
  // position:relative with a fixed aspect ratio, and both the canvas and the
  // overlay are absolutely positioned inside it, so losing it collapses the
  // whole game page. It lives here rather than at the call site now, because it
  // is structural to this component rather than a caller's choice.
  <template>
    <div class="arcade-frame" ...attributes>
      {{#if this.frameSrc}}
        <iframe
          class="arcade-frame-canvas"
          src={{this.frameSrc}}
          sandbox="allow-scripts"
          title={{@game.name}}
          scrolling="no"
          {{didInsert this.registerFrame}}
        ></iframe>
      {{/if}}

      {{#if this.overlayVisible}}
        <div class="arcade-frame-overlay">
          {{#if (eq this.status "idle")}}
            <button
              type="button"
              class="btn btn-primary arcade-frame-start"
              {{on "click" this.start}}
            >
              Play
              {{@game.name}}
            </button>
            <p class="arcade-frame-hint">Swipe, or use the arrow keys.</p>

          {{else if (eq this.status "loading")}}
            <p class="arcade-frame-status">Starting…</p>

          {{else if (eq this.status "saving")}}
            <p class="arcade-frame-status">Saving your score…</p>

          {{else if (eq this.status "done")}}
            <div class="arcade-frame-result">
              {{#if this.error}}
                <p class="arcade-frame-error">{{this.error}}</p>
              {{else}}
                <p class="arcade-frame-score">
                  {{this.lastScore}}
                  <span class="arcade-frame-unit">{{@game.score_unit}}</span>
                </p>
                {{#if this.isPersonalBest}}
                  <p class="arcade-frame-badge">{{icon "star"}}
                    New personal best</p>
                {{/if}}
              {{/if}}
              <button
                type="button"
                class="btn btn-primary"
                {{on "click" this.start}}
              >Play again</button>
            </div>
          {{/if}}
        </div>
      {{/if}}
    </div>
  </template>
}
