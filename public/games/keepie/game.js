/* Keepie Uppie for the Discourse arcade. One run, one score: no in-game restart.
 *
 * Tap the ball to send it back up. Where you hit it decides which way it goes,
 * so a good player steers it back under themselves instead of chasing it into a
 * wall. Gravity climbs and the ball shrinks with every touch.
 */
(function () {
  "use strict";

  let A = window.Arcade;

  let STEP_MS = 16;

  let GROUND_Y = 0.94;
  let BALL_R_START = 0.055;
  let BALL_R_MIN = 0.032;
  let SHRINK_OVER = 40; // touches to reach the smallest ball

  let GRAVITY_BASE = 0.00085;
  let GRAVITY_MAX_FACTOR = 2.2;
  let KICK = 0.0235;
  let AIM_STRENGTH = 0.14;
  let MAX_VX = 0.014;

  let WALL_DAMPING = 0.9;
  let CEILING_DAMPING = 0.6;

  // A tap this much wider than the ball still counts, so a moving target stays
  // fair on a phone.
  let HIT_SLACK = 1.7;
  let COOLDOWN_STEPS = 5;
  let FLASH_STEPS = 9;

  let stage = document.getElementById("stage");
  let view = A.canvas(document.getElementById("view"));
  let scoreEl = document.getElementById("score");
  let overEl = document.getElementById("over");

  // Opens as if the ball was just kicked up, so the first touch has the same
  // rhythm as every touch after it. Dropping it from a height instead would
  // make the opening the fastest moment of the whole run.
  let ball = { x: 0.5, y: 0.6, vx: 0.002, vy: -KICK };
  let touches = 0;
  let cooldown = 0;
  let flash = null;
  let alive = true;

  function size() {
    return Math.min(view.w, view.h);
  }

  function ballRadius() {
    let t = Math.min(1, touches / SHRINK_OVER);
    return BALL_R_START + (BALL_R_MIN - BALL_R_START) * t;
  }

  function gravity() {
    let factor = Math.min(GRAVITY_MAX_FACTOR, 1 + touches * 0.02);
    return GRAVITY_BASE * factor;
  }

  function clamp(value, low, high) {
    return Math.min(high, Math.max(low, value));
  }

  function finish() {
    alive = false;
    overEl.classList.add("visible");
    A.submit(touches);
  }

  function kick(point) {
    if (!alive || cooldown > 0) {
      return;
    }

    let s = size();
    let tap = { x: point.x / s, y: point.y / s };
    let r = ballRadius();
    let dx = tap.x - ball.x;
    let dy = tap.y - ball.y;

    if (Math.hypot(dx, dy) > r * HIT_SLACK) {
      return;
    }

    // Hitting the left of the ball sends it right, and the other way round.
    ball.vy = -KICK;
    ball.vx = clamp(ball.vx - dx * AIM_STRENGTH, -MAX_VX, MAX_VX);

    touches++;
    cooldown = COOLDOWN_STEPS;
    flash = { x: tap.x, y: tap.y, life: FLASH_STEPS };
    scoreEl.textContent = String(touches);
  }

  function step() {
    if (!alive) {
      return;
    }

    if (cooldown > 0) {
      cooldown--;
    }

    if (flash) {
      flash.life--;
      if (flash.life <= 0) {
        flash = null;
      }
    }

    let r = ballRadius();

    ball.vy += gravity();
    ball.x += ball.vx;
    ball.y += ball.vy;

    if (ball.x - r < 0) {
      ball.x = r;
      ball.vx = Math.abs(ball.vx) * WALL_DAMPING;
    } else if (ball.x + r > 1) {
      ball.x = 1 - r;
      ball.vx = -Math.abs(ball.vx) * WALL_DAMPING;
    }

    if (ball.y - r < 0) {
      ball.y = r;
      ball.vy = Math.abs(ball.vy) * CEILING_DAMPING;
    }

    if (ball.y + r >= GROUND_Y) {
      ball.y = GROUND_Y - r;
      finish();
    }
  }

  function draw() {
    let ctx = view.ctx;
    let s = size();
    let r = ballRadius();

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    // Ground
    ctx.save();
    ctx.globalAlpha = 0.45;
    ctx.strokeStyle = A.theme.muted;
    ctx.lineWidth = Math.max(1.5, s * 0.005);
    ctx.beginPath();
    ctx.moveTo(0, GROUND_Y * s);
    ctx.lineTo(s, GROUND_Y * s);
    ctx.stroke();
    ctx.restore();

    // Shadow. How tight and dark it is says how close the ball is to the
    // ground, which is what makes the timing readable.
    let height = clamp((GROUND_Y - ball.y) / GROUND_Y, 0, 1);
    ctx.save();
    ctx.globalAlpha = 0.05 + (1 - height) * 0.22;
    ctx.fillStyle = A.theme.fg;
    ctx.beginPath();
    ctx.ellipse(
      ball.x * s,
      GROUND_Y * s,
      r * s * (0.75 + height * 0.55),
      r * s * 0.28,
      0,
      0,
      Math.PI * 2
    );
    ctx.fill();
    ctx.restore();

    // Kick flash
    if (flash) {
      let t = flash.life / FLASH_STEPS;
      ctx.save();
      ctx.globalAlpha = t * 0.6;
      ctx.strokeStyle = A.theme.accent;
      ctx.lineWidth = Math.max(1.5, s * 0.006);
      ctx.beginPath();
      ctx.arc(flash.x * s, flash.y * s, r * s * (1.1 + (1 - t) * 0.9), 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }

    // Ball
    ctx.fillStyle = A.theme.fg;
    ctx.beginPath();
    ctx.arc(ball.x * s, ball.y * s, r * s, 0, Math.PI * 2);
    ctx.fill();

    // A single panel marking, so the ball reads as a ball and its spin is felt.
    ctx.save();
    ctx.globalAlpha = 0.55;
    ctx.fillStyle = A.theme.low;
    let panelShift = clamp(-ball.vx * 5, -r * 0.45, r * 0.45);
    ctx.beginPath();
    ctx.arc(
      (ball.x + panelShift) * s,
      (ball.y - r * 0.35) * s,
      r * s * 0.3,
      0,
      Math.PI * 2
    );
    ctx.fill();
    ctx.restore();
  }

  // Read-only state for the specs, so a test can tap the ball accurately and
  // check the game is actually playable rather than only that it ends. Nothing
  // here sets anything, and scores are validated server side regardless.
  window.Keepie = {
    state: function () {
      return {
        x: ball.x,
        y: ball.y,
        vy: ball.vy,
        r: ballRadius(),
        slack: HIT_SLACK,
        touches,
        alive,
        ground: GROUND_Y,
      };
    },
  };

  A.onTap(stage, kick);

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
