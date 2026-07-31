import { tracked } from "@glimmer/tracking";
import Component from "@ember/component";
import { action } from "@ember/object";
import { scheduleOnce } from "@ember/runloop";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

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
  _messageHandler = null;

  didInsertElement() {
    super.didInsertElement(...arguments);
    this._messageHandler = (event) => this._onMessage(event);
    window.addEventListener("message", this._messageHandler);
  }

  willDestroyElement() {
    super.willDestroyElement(...arguments);
    if (this._messageHandler) {
      window.removeEventListener("message", this._messageHandler);
      this._messageHandler = null;
    }
  }

  get overlayVisible() {
    return this.status !== "playing";
  }

  @action
  async start() {
    this.error = null;
    this.status = "loading";

    try {
      const { token } = await ajax(
        `/arcade/api/games/${this.game.slug}/runs.json`,
        { type: "POST" }
      );

      this._token = token;
      this._runCount += 1;
      this.lastScore = null;
      this.isPersonalBest = false;
      this.frameSrc = this._buildFrameSrc();
      this.status = "playing";
      scheduleOnce("afterRender", this, "_focusFrame");
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

    return `${this.game.play_url}?${params.toString()}`;
  }

  _frameEl() {
    return this.element?.querySelector("iframe");
  }

  _focusFrame() {
    this._frameEl()?.focus();
  }

  // The frame is sandboxed without allow-same-origin, so its origin is opaque
  // and event.origin is useless. Comparing event.source against our own frame
  // is the reliable check.
  _onMessage(event) {
    const frame = this._frameEl();
    if (!frame || event.source !== frame.contentWindow) {
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
      this.onScore?.(payload);
    } catch (e) {
      this.error =
        e.jqXHR?.responseJSON?.error || "That score could not be saved.";
      this.status = "done";
    }
  }
}
