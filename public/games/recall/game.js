/* Recall for the Discourse arcade. One run, one score: no in-game restart.
 *
 * The Simon shape. Tone matters as much as colour here, because what you are
 * really memorising is a little tune, so the pads play notes. Audio is generated
 * rather than loaded, and browsers only allow it after a gesture inside this
 * document, which is what the "Tap to begin" panel is for: nobody opens the
 * arcade and gets ambushed by beeping.
 *
 * Score is rounds completed. Colour is never the only cue: each pad keeps its
 * own corner and its own note.
 */
(function () {
  "use strict";

  const A = window.Arcade;

  const PADS = 4;
  const LEAD_IN_MS = 600;
  const FLASH_START_MS = 520;
  const FLASH_FLOOR_MS = 220;
  const FLASH_STEP_MS = 12;
  const GAP_RATIO = 0.4;
  const GAP_FLOOR_MS = 90;
  const HAND_OVER_MS = 300;
  const INPUT_TIMEOUT_MS = 3500;

  // The pitches the original used, low to high across the four pads.
  const TONES = [329.63, 277.18, 220.0, 164.81];
  const WRONG_TONE = 110.0;

  const padsEl = document.getElementById("pads");
  const pads = Array.prototype.slice.call(
    document.getElementsByClassName("pad")
  );
  const scoreEl = document.getElementById("score");
  const roundEl = document.getElementById("round");
  const muteEl = document.getElementById("mute");
  const beginEl = document.getElementById("begin");
  const overEl = document.getElementById("over");

  let sequence = [];
  let expected = 0;
  let score = 0;
  let phase = "waiting"; // waiting | showing | input | over
  let muted = false;
  let audio = null;
  let timers = [];
  let inputTimer = null;

  // ── Sound ────────────────────────────────────────────────

  function unlockAudio() {
    if (audio) {
      return;
    }
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) {
      return;
    }
    try {
      audio = new Ctx();
    } catch {
      // No sound available, which the game plays fine without.
      audio = null;
    }
  }

  function tone(frequency, seconds, type) {
    if (!audio || muted) {
      return;
    }

    const osc = audio.createOscillator();
    const gain = audio.createGain();
    const now = audio.currentTime;

    osc.type = type || "sine";
    osc.frequency.value = frequency;

    // A short ramp at each end, otherwise every note starts with a click.
    gain.gain.setValueAtTime(0, now);
    gain.gain.linearRampToValueAtTime(0.18, now + 0.012);
    gain.gain.setValueAtTime(0.18, now + seconds - 0.03);
    gain.gain.linearRampToValueAtTime(0, now + seconds);

    osc.connect(gain);
    gain.connect(audio.destination);
    osc.start(now);
    osc.stop(now + seconds + 0.02);
  }

  // ── Timing helpers ───────────────────────────────────────

  function later(fn, ms) {
    const id = setTimeout(fn, ms);
    timers.push(id);
    return id;
  }

  function clearTimers() {
    timers.forEach(clearTimeout);
    timers = [];
    if (inputTimer) {
      clearTimeout(inputTimer);
      inputTimer = null;
    }
  }

  function flashMs() {
    return Math.max(
      FLASH_FLOOR_MS,
      FLASH_START_MS - (sequence.length - 1) * FLASH_STEP_MS
    );
  }

  function gapMs() {
    return Math.max(GAP_FLOOR_MS, Math.round(flashMs() * GAP_RATIO));
  }

  // ── Pads ─────────────────────────────────────────────────

  function light(index, ms) {
    const pad = pads[index];
    if (!pad) {
      return;
    }

    pad.classList.add("lit");
    tone(TONES[index], ms / 1000);
    later(function () {
      pad.classList.remove("lit");
    }, ms);
  }

  // ── Rounds ───────────────────────────────────────────────

  function nextRound() {
    sequence.push(Math.floor(Math.random() * PADS));
    expected = 0;
    phase = "showing";
    padsEl.classList.add("watching");
    roundEl.textContent = "Watch the sequence";

    const on = flashMs();
    const gap = gapMs();

    sequence.forEach(function (index, position) {
      later(function () {
        light(index, on);
      }, LEAD_IN_MS + position * (on + gap));
    });

    later(function () {
      phase = "input";
      padsEl.classList.remove("watching");
      roundEl.textContent = "Your turn";
      armInputTimeout();
    }, LEAD_IN_MS + sequence.length * (on + gap) + HAND_OVER_MS);
  }

  function armInputTimeout() {
    if (inputTimer) {
      clearTimeout(inputTimer);
    }
    inputTimer = setTimeout(function () {
      finish("Too slow");
    }, INPUT_TIMEOUT_MS);
  }

  function finish(message) {
    if (phase === "over") {
      return;
    }

    clearTimers();
    phase = "over";
    padsEl.classList.add("watching");
    overEl.textContent = message;
    overEl.classList.add("visible");
    tone(WRONG_TONE, 0.55, "sawtooth");
    A.submit(score);
  }

  function press(index) {
    if (phase !== "input") {
      return;
    }

    light(index, 180);

    if (sequence[expected] !== index) {
      finish("Wrong pad");
      return;
    }

    expected++;

    if (expected < sequence.length) {
      armInputTimeout();
      return;
    }

    // Round complete.
    if (inputTimer) {
      clearTimeout(inputTimer);
      inputTimer = null;
    }

    score = sequence.length;
    scoreEl.textContent = String(score);
    phase = "showing";
    padsEl.classList.add("watching");
    roundEl.textContent = "Nice";
    later(nextRound, 700);
  }

  // ── Input ────────────────────────────────────────────────

  pads.forEach(function (pad, index) {
    pad.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      press(index);
    });
  });

  muteEl.addEventListener("pointerdown", function (event) {
    event.preventDefault();
    event.stopPropagation();
    muted = !muted;
    muteEl.textContent = muted ? "sound off" : "sound on";
  });

  function begin() {
    if (phase !== "waiting") {
      return;
    }
    // The gesture that lets this document play audio at all.
    unlockAudio();
    beginEl.classList.add("gone");
    nextRound();
  }

  beginEl.addEventListener("pointerdown", function (event) {
    event.preventDefault();
    begin();
  });

  // Read-only, for the specs, same convention as the other games. A spec cannot
  // watch pads flash reliably, so it reads the sequence and plays it back. Reads
  // state and sets nothing.
  window.Recall = {
    state() {
      return {
        sequence: sequence.slice(),
        expected,
        score,
        phase,
      };
    },
  };

  A.ready();
})();
