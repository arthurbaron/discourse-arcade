/* Penalty for the Discourse arcade. One run, one score: no in-game restart.
 *
 * The keeper slides across the goal the whole time, so this is a timing and
 * placement game rather than a guess. Pick your moment, then place the shot
 * away from where the keeper can reach. The keeper reads the shot and lunges,
 * and both their patrol speed and their reach grow with every goal you score.
 */
(function () {
  "use strict";

  let A = window.Arcade;

  let STEP_MS = 16;
  let START_LIVES = 3;

  // Goal mouth, as fractions of the square stage.
  let GOAL_LEFT = 0.12;
  let GOAL_RIGHT = 0.88;
  let GOAL_TOP = 0.15;
  let GOAL_BOTTOM = 0.53;

  let KEEPER_W = 0.115;
  let KEEPER_H = 0.19;
  // Standing height, from which the keeper dives up and sideways. Without a
  // vertical dive the whole top half of the goal is a free goal.
  let KEEPER_REST_Y = GOAL_BOTTOM - KEEPER_H / 2;
  let KEEPER_RECOVER = 0.013;

  // Inaccuracy grows the further from the middle of the goal you aim, so a
  // corner is an ambitious shot rather than a free one, while a comfortable
  // shot goes roughly where you put it.
  let GOAL_MID_X = (GOAL_LEFT + GOAL_RIGHT) / 2;
  let GOAL_MID_Y = (GOAL_TOP + GOAL_BOTTOM) / 2;
  let MAX_AIM_OFFSET = Math.hypot(
    GOAL_RIGHT - GOAL_MID_X,
    GOAL_BOTTOM - GOAL_MID_Y
  );
  let SPREAD_BASE = 0.012;
  let SPREAD_EXTRA = 0.032;

  function spreadFor(point) {
    let offset = Math.hypot(point.x - GOAL_MID_X, point.y - GOAL_MID_Y);
    return SPREAD_BASE + (Math.min(1, offset / MAX_AIM_OFFSET) * SPREAD_EXTRA);
  }

  let SPOT_X = 0.5;
  let SPOT_Y = 0.87;
  let BALL_R = 0.028;

  let FLIGHT_STEPS = 28;
  let RESULT_STEPS = 42;
  let MIN_DRAG = 0.08;

  let stage = document.getElementById("stage");
  let view = A.canvas(document.getElementById("view"));
  let scoreEl = document.getElementById("score");
  let hintEl = document.getElementById("hint");
  let overEl = document.getElementById("over");

  let phase = "aiming"; // aiming | flying | result
  let timer = 0;
  let goals = 0;
  let lives = START_LIVES;
  let alive = true;

  let keeper = { x: 0.5, y: KEEPER_REST_Y, dir: 1, lunge: 0 };
  let ball = { x: SPOT_X, y: SPOT_Y };
  let shot = null;
  let guide = null;
  let outcome = "";

  function size() {
    return Math.min(view.w, view.h);
  }

  function keeperSpeed() {
    return Math.min(0.019, 0.0055 + goals * 0.0007);
  }

  // Tuned by measurement, not by feel. At 0.010 the keeper covered 0.16 of a
  // dive while a top corner sits 0.43 away, so the corners were free. He now
  // reaches a badly timed shot and still cannot reach a corner picked while he
  // is at the far post, which is the whole game.
  function keeperLungeSpeed() {
    return Math.min(0.04, 0.021 + goals * 0.0009);
  }

  function keeperReactionSteps() {
    return Math.max(4, 10 - Math.floor(goals / 2));
  }

  function keeperBox() {
    return {
      left: keeper.x - KEEPER_W / 2,
      right: keeper.x + KEEPER_W / 2,
      top: keeper.y - KEEPER_H / 2,
      bottom: keeper.y + KEEPER_H / 2,
    };
  }

  function clamp(value, low, high) {
    return Math.min(high, Math.max(low, value));
  }

  function updateHint() {
    // A click places the shot just as well as a drag does, so the hint should
    // not promise a gesture that is not required.
    hintEl.innerHTML =
      "Aim anywhere in the goal &middot; Lives " + Math.max(0, lives);
  }

  function finish() {
    alive = false;
    overEl.textContent = "Game over";
    overEl.classList.add("visible");
    A.submit(goals);
  }

  function nextPenalty() {
    ball.x = SPOT_X;
    ball.y = SPOT_Y;
    shot = null;
    guide = null;
    keeper.lunge = 0;
    phase = "aiming";
  }

  function concede(label) {
    outcome = label;
    lives--;
    updateHint();
    phase = "result";
    timer = RESULT_STEPS;
  }

  function celebrate() {
    outcome = "GOAL";
    goals++;
    scoreEl.textContent = String(goals);
    phase = "result";
    timer = RESULT_STEPS;
  }

  // All four sides of the goal mouth, which took two goes to get right. The
  // first version checked the crossbar and the posts and forgot the goal line,
  // so the whole strip of ground between the line and the ball counted as a shot
  // on target. The keeper's box bottoms out at the line and cannot go below it,
  // so that strip was not a chance, it was a certainty.
  function targetVerdict(target) {
    if (target.y < GOAL_TOP) {
      return "OVER";
    }
    if (target.y > GOAL_BOTTOM) {
      return "SHORT";
    }
    if (target.x < GOAL_LEFT || target.x > GOAL_RIGHT) {
      return "WIDE";
    }
    return null;
  }

  function shoot(from, to) {
    if (phase !== "aiming" || !alive) {
      return;
    }

    let dx = to.x - ball.x;
    let dy = to.y - ball.y;

    // A tap or a downward flick is not a shot, so it costs nothing.
    if (Math.hypot(dx, dy) < MIN_DRAG || dy > -MIN_DRAG) {
      guide = null;
      return;
    }

    // Where you released, plus a little inaccuracy. The verdict is worked out
    // after the spread, so a shot aimed a hair inside the post can still go
    // wide. That is what stops corner-hunting from being a free goal.
    let spread = spreadFor(to);
    let target = {
      x: to.x + (Math.random() * 2 - 1) * spread,
      y: to.y + (Math.random() * 2 - 1) * spread,
    };

    shot = {
      fromX: ball.x,
      fromY: ball.y,
      toX: target.x,
      toY: target.y,
      verdict: targetVerdict(target),
      step: 0,
    };

    guide = null;
    phase = "flying";
    timer = 0;
  }

  function patrolKeeper() {
    keeper.x += keeper.dir * keeperSpeed();

    let minX = GOAL_LEFT + KEEPER_W / 2;
    let maxX = GOAL_RIGHT - KEEPER_W / 2;

    if (keeper.x <= minX) {
      keeper.x = minX;
      keeper.dir = 1;
    } else if (keeper.x >= maxX) {
      keeper.x = maxX;
      keeper.dir = -1;
    }

    // Back on his feet after a dive.
    let drop = KEEPER_REST_Y - keeper.y;
    if (Math.abs(drop) > 0.0005) {
      keeper.y += Math.sign(drop) * Math.min(Math.abs(drop), KEEPER_RECOVER);
    }
  }

  function lungeKeeper() {
    keeper.lunge++;
    if (keeper.lunge <= keeperReactionSteps()) {
      patrolKeeper();
      return;
    }

    // Dives at the ball in both axes. How far he gets is the whole contest:
    // a corner reached from the far post is a longer dive than the flight
    // allows, which is why timing the patrol matters as much as placement.
    let reach = keeperLungeSpeed();
    let dx = shot.toX - keeper.x;
    let dy = shot.toY - keeper.y;
    let dist = Math.hypot(dx, dy);

    if (dist <= reach) {
      keeper.x = shot.toX;
      keeper.y = shot.toY;
    } else {
      keeper.x += (dx / dist) * reach;
      keeper.y += (dy / dist) * reach;
    }

    keeper.x = clamp(
      keeper.x,
      GOAL_LEFT + KEEPER_W / 2,
      GOAL_RIGHT - KEEPER_W / 2
    );
    // He can leave the ground but not the goal, and not sink into it.
    keeper.y = clamp(keeper.y, GOAL_TOP + KEEPER_H / 2, KEEPER_REST_Y);
  }

  function resolveShot() {
    if (shot.verdict) {
      concede(shot.verdict);
      return;
    }

    let box = keeperBox();
    let reachesBall =
      ball.x + BALL_R > box.left &&
      ball.x - BALL_R < box.right &&
      ball.y + BALL_R > box.top &&
      ball.y - BALL_R < box.bottom;

    if (reachesBall) {
      concede("SAVED");
    } else {
      celebrate();
    }
  }

  function step() {
    if (!alive) {
      return;
    }

    if (phase === "aiming") {
      patrolKeeper();
      return;
    }

    if (phase === "flying") {
      lungeKeeper();

      shot.step++;
      let t = Math.min(1, shot.step / FLIGHT_STEPS);
      ball.x = shot.fromX + (shot.toX - shot.fromX) * t;
      ball.y = shot.fromY + (shot.toY - shot.fromY) * t;

      if (t >= 1) {
        resolveShot();
      }
      return;
    }

    // result
    patrolKeeper();
    timer--;

    if (timer > 0) {
      return;
    }

    if (lives <= 0) {
      finish();
    } else {
      nextPenalty();
    }
  }

  function drawGoal(ctx, s) {
    let left = GOAL_LEFT * s;
    let right = GOAL_RIGHT * s;
    let top = GOAL_TOP * s;
    let bottom = GOAL_BOTTOM * s;

    // Net
    ctx.save();
    ctx.globalAlpha = 0.28;
    ctx.strokeStyle = A.theme.muted;
    ctx.lineWidth = Math.max(1, s * 0.002);
    let steps = 9;
    for (let i = 1; i < steps; i++) {
      let x = left + ((right - left) * i) / steps;
      ctx.beginPath();
      ctx.moveTo(x, top);
      ctx.lineTo(x, bottom);
      ctx.stroke();
    }
    for (let j = 1; j < 5; j++) {
      let y = top + ((bottom - top) * j) / 5;
      ctx.beginPath();
      ctx.moveTo(left, y);
      ctx.lineTo(right, y);
      ctx.stroke();
    }
    ctx.restore();

    // Frame
    ctx.strokeStyle = A.theme.fg;
    ctx.lineWidth = Math.max(2, s * 0.011);
    ctx.beginPath();
    ctx.moveTo(left, bottom);
    ctx.lineTo(left, top);
    ctx.lineTo(right, top);
    ctx.lineTo(right, bottom);
    ctx.stroke();

    // Goal line
    ctx.save();
    ctx.globalAlpha = 0.45;
    ctx.lineWidth = Math.max(1, s * 0.004);
    ctx.beginPath();
    ctx.moveTo(left - s * 0.04, bottom);
    ctx.lineTo(right + s * 0.04, bottom);
    ctx.stroke();
    ctx.restore();
  }

  function drawKeeper(ctx, s) {
    let box = keeperBox();
    ctx.fillStyle = A.theme.accent;
    ctx.fillRect(
      box.left * s,
      box.top * s,
      KEEPER_W * s,
      KEEPER_H * s
    );

    // Gloves, so the reach is readable at a glance.
    let glove = KEEPER_W * 0.3;
    ctx.fillRect(
      (box.left - glove * 0.5) * s,
      (box.top + KEEPER_H * 0.18) * s,
      glove * s,
      glove * s
    );
    ctx.fillRect(
      (box.right - glove * 0.5) * s,
      (box.top + KEEPER_H * 0.18) * s,
      glove * s,
      glove * s
    );
  }

  function drawGuide(ctx, s) {
    if (!guide) {
      return;
    }

    let bad = !!targetVerdict(guide);

    ctx.save();
    ctx.globalAlpha = bad ? 0.35 : 0.75;
    ctx.strokeStyle = bad ? A.theme.muted : A.theme.accent;
    ctx.lineWidth = Math.max(1.5, s * 0.005);
    ctx.setLineDash([s * 0.02, s * 0.018]);
    ctx.beginPath();
    ctx.moveTo(ball.x * s, ball.y * s);
    ctx.lineTo(guide.x * s, guide.y * s);
    ctx.stroke();
    ctx.setLineDash([]);

    ctx.beginPath();
    ctx.arc(guide.x * s, guide.y * s, s * 0.022, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  function drawOutcome(ctx, s) {
    if (phase !== "result") {
      return;
    }

    ctx.save();
    ctx.fillStyle = outcome === "GOAL" ? A.theme.accent : A.theme.fg;
    ctx.font = "700 " + Math.round(s * 0.1) + "px -apple-system, Helvetica, Arial, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(outcome, s * 0.5, s * 0.68);
    ctx.restore();
  }

  function draw() {
    let ctx = view.ctx;
    let s = size();

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    drawGoal(ctx, s);
    drawKeeper(ctx, s);
    drawGuide(ctx, s);

    // Penalty spot
    ctx.save();
    ctx.globalAlpha = 0.35;
    ctx.fillStyle = A.theme.muted;
    ctx.beginPath();
    ctx.arc(SPOT_X * s, SPOT_Y * s, s * 0.008, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    ctx.fillStyle = A.theme.fg;
    ctx.beginPath();
    ctx.arc(ball.x * s, ball.y * s, BALL_R * s, 0, Math.PI * 2);
    ctx.fill();

    drawOutcome(ctx, s);
  }

  function normalise(point) {
    let s = size();
    return { x: point.x / s, y: point.y / s };
  }

  A.onAim(stage, {
    onMove: function (from, to) {
      if (phase !== "aiming" || !alive) {
        return;
      }
      guide = normalise(to);
    },
    onRelease: function (from, to) {
      shoot(normalise(from), normalise(to));
    },
    onCancel: function () {
      guide = null;
    },
  });

  // Read-only, for the specs, same convention as the other games. The outcome
  // of a shot is drawn on the canvas, so without this a spec cannot tell a goal
  // from a save. Reads state and sets nothing.
  window.Penalty = {
    state() {
      return {
        goals,
        lives,
        phase,
        outcome,
        keeper: { x: keeper.x, y: keeper.y },
      };
    },
  };

  updateHint();

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
