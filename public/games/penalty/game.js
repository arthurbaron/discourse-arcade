/* Penalty for the Discourse arcade. One run, one score: no in-game restart.
 *
 * The keeper slides across the goal the whole time, so this is a timing and
 * placement game rather than a guess. Pick your moment, then place the shot
 * away from where the keeper can reach. The keeper reads the shot and lunges,
 * and both their patrol speed and their reach grow with every goal you score.
 */
(function () {
  "use strict";

  var A = window.Arcade;

  var STEP_MS = 16;
  var START_LIVES = 3;

  // Goal mouth, as fractions of the square stage.
  var GOAL_LEFT = 0.12;
  var GOAL_RIGHT = 0.88;
  var GOAL_TOP = 0.15;
  var GOAL_BOTTOM = 0.53;

  var KEEPER_W = 0.115;
  var KEEPER_H = 0.19;

  var SPOT_X = 0.5;
  var SPOT_Y = 0.87;
  var BALL_R = 0.028;

  var FLIGHT_STEPS = 28;
  var RESULT_STEPS = 42;
  var MIN_DRAG = 0.08;

  var stage = document.getElementById("stage");
  var view = A.canvas(document.getElementById("view"));
  var scoreEl = document.getElementById("score");
  var hintEl = document.getElementById("hint");
  var overEl = document.getElementById("over");

  var phase = "aiming"; // aiming | flying | result
  var timer = 0;
  var goals = 0;
  var lives = START_LIVES;
  var alive = true;

  var keeper = { x: 0.5, dir: 1, lunge: 0 };
  var ball = { x: SPOT_X, y: SPOT_Y };
  var shot = null;
  var guide = null;
  var outcome = "";

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

    var dx = to.x - ball.x;
    var dy = to.y - ball.y;

    // A tap or a downward flick is not a shot, so it costs nothing.
    if (Math.hypot(dx, dy) < MIN_DRAG || dy > -MIN_DRAG) {
      guide = null;
      return;
    }

    // Aim past the goal line a touch so the ball visibly crosses it.
    var target = { x: to.x, y: to.y };

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

    var minX = GOAL_LEFT + KEEPER_W / 2;
    var maxX = GOAL_RIGHT - KEEPER_W / 2;

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

    var wanted = shot.toX;
    var delta = wanted - keeper.x;
    var reach = keeperLungeSpeed();

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

    var box = keeperBox();
    var reachesBall =
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
      var t = Math.min(1, shot.step / FLIGHT_STEPS);
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
    var left = GOAL_LEFT * s;
    var right = GOAL_RIGHT * s;
    var top = GOAL_TOP * s;
    var bottom = GOAL_BOTTOM * s;

    // Net
    ctx.save();
    ctx.globalAlpha = 0.28;
    ctx.strokeStyle = A.theme.muted;
    ctx.lineWidth = Math.max(1, s * 0.002);
    var steps = 9;
    for (var i = 1; i < steps; i++) {
      var x = left + ((right - left) * i) / steps;
      ctx.beginPath();
      ctx.moveTo(x, top);
      ctx.lineTo(x, bottom);
      ctx.stroke();
    }
    for (var j = 1; j < 5; j++) {
      var y = top + ((bottom - top) * j) / 5;
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
    var box = keeperBox();
    ctx.fillStyle = A.theme.accent;
    ctx.fillRect(
      box.left * s,
      box.top * s,
      KEEPER_W * s,
      KEEPER_H * s
    );

    // Gloves, so the reach is readable at a glance.
    var glove = KEEPER_W * 0.3;
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

    var bad = !!targetVerdict(guide);

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
    var ctx = view.ctx;
    var s = size();

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
    var s = size();
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
