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

  let keeper = { x: 0.5, dir: 1, lunge: 0 };
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

  function keeperLungeSpeed() {
    return Math.min(0.032, 0.010 + goals * 0.0009);
  }

  function keeperReactionSteps() {
    return Math.max(4, 12 - Math.floor(goals / 2));
  }

  function keeperBox() {
    return {
      left: keeper.x - KEEPER_W / 2,
      right: keeper.x + KEEPER_W / 2,
      top: GOAL_BOTTOM - KEEPER_H,
      bottom: GOAL_BOTTOM,
    };
  }

  function updateHint() {
    hintEl.innerHTML =
      "Drag from the ball to shoot &middot; Lives " + Math.max(0, lives);
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

  function targetVerdict(target) {
    if (target.y < GOAL_TOP) {
      return "OVER";
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

    // Aim past the goal line a touch so the ball visibly crosses it.
    let target = { x: to.x, y: to.y };

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
  }

  function lungeKeeper() {
    keeper.lunge++;
    if (keeper.lunge <= keeperReactionSteps()) {
      patrolKeeper();
      return;
    }

    let wanted = shot.toX;
    let delta = wanted - keeper.x;
    let reach = keeperLungeSpeed();

    if (Math.abs(delta) <= reach) {
      keeper.x = wanted;
    } else {
      keeper.x += Math.sign(delta) * reach;
    }

    keeper.x = Math.min(
      GOAL_RIGHT - KEEPER_W / 2,
      Math.max(GOAL_LEFT + KEEPER_W / 2, keeper.x)
    );
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

  updateHint();

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
