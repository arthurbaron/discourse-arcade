/* Breakout for the Discourse arcade. One run, one score: no in-game restart.
 * Drag anywhere on the stage to move the paddle, or use the arrow keys.
 */
(function () {
  "use strict";

  var A = window.Arcade;

  var STEP_MS = 16;
  var COLS = 8;
  var ROWS = 5;
  var START_LIVES = 3;
  var LAUNCH_DELAY_STEPS = 45;

  // Everything is a fraction of the stage, so the game scales with the frame.
  var MARGIN_X = 0.04;
  var BRICK_GAP = 0.008;
  var BRICK_TOP = 0.1;
  var BRICK_H = 0.045;
  var PADDLE_W = 0.2;
  var PADDLE_H = 0.025;
  var PADDLE_Y = 0.93;
  var BALL_R = 0.017;
  var BASE_SPEED = 0.0105;
  var MAX_SPEED = 0.024;
  var KEY_NUDGE = 0.06;

  var stage = document.getElementById("stage");
  var view = A.canvas(document.getElementById("view"));
  var scoreEl = document.getElementById("score");
  var hintEl = document.getElementById("hint");
  var overEl = document.getElementById("over");

  var bricks = [];
  var paddleRatio = 0.5;
  var ball = { x: 0, y: 0, vx: 0, vy: 0 };
  var score = 0;
  var lives = START_LIVES;
  var level = 1;
  var waiting = LAUNCH_DELAY_STEPS;
  var alive = true;

  function size() {
    return Math.min(view.w, view.h);
  }

  function buildBricks() {
    bricks = [];
    var span = 1 - MARGIN_X * 2 - BRICK_GAP * (COLS - 1);
    var brickW = span / COLS;

    for (var row = 0; row < ROWS; row++) {
      for (var col = 0; col < COLS; col++) {
        bricks.push({
          x: MARGIN_X + col * (brickW + BRICK_GAP),
          y: BRICK_TOP + row * (BRICK_H + BRICK_GAP),
          w: brickW,
          h: BRICK_H,
          row: row,
          alive: true,
        });
      }
    }
  }

  function levelSpeed() {
    return Math.min(MAX_SPEED, BASE_SPEED * (1 + 0.14 * (level - 1)));
  }

  function resetBall() {
    ball.x = paddleRatio;
    ball.y = PADDLE_Y - PADDLE_H - BALL_R;
    ball.vx = 0;
    ball.vy = 0;
    waiting = LAUNCH_DELAY_STEPS;
  }

  function launch() {
    var speed = levelSpeed();
    // Angle measured from straight up, so the launch is always steep enough
    // to leave the paddle but never close to horizontal.
    var degrees = 25 + Math.random() * 25;
    var angle =
      degrees * (Math.PI / 180) * (Math.random() < 0.5 ? -1 : 1);

    ball.vx = Math.sin(angle) * speed;
    ball.vy = -Math.abs(Math.cos(angle)) * speed;
  }

  function updateHint() {
    hintEl.innerHTML =
      "Level " + level + " &middot; Lives " + Math.max(0, lives);
  }

  function finish(message) {
    alive = false;
    overEl.textContent = message;
    overEl.classList.add("visible");
    A.submit(score);
  }

  function addScore(points) {
    score += points;
    scoreEl.textContent = String(score);
  }

  function bricksLeft() {
    for (var i = 0; i < bricks.length; i++) {
      if (bricks[i].alive) {
        return true;
      }
    }
    return false;
  }

  function nextLevel() {
    addScore(100 * level);
    level++;
    buildBricks();
    updateHint();
    resetBall();
  }

  function loseLife() {
    lives--;
    updateHint();

    if (lives <= 0) {
      finish("Game over");
      return;
    }

    resetBall();
  }

  function bounceOffPaddle() {
    var half = PADDLE_W / 2;
    var top = PADDLE_Y - PADDLE_H;

    if (ball.vy <= 0 || ball.y + BALL_R < top) {
      return false;
    }
    if (ball.x < paddleRatio - half || ball.x > paddleRatio + half) {
      return false;
    }

    // Where it lands on the paddle sets the outgoing angle, so the paddle is
    // an aiming tool rather than just a wall.
    var offset = (ball.x - paddleRatio) / half;
    var speed = Math.min(
      MAX_SPEED,
      Math.hypot(ball.vx, ball.vy) * 1.008
    );
    var angle = offset * (60 * (Math.PI / 180));

    ball.vx = Math.sin(angle) * speed;
    ball.vy = -Math.abs(Math.cos(angle) * speed);
    ball.y = top - BALL_R;
    return true;
  }

  function bounceOffBricks() {
    for (var i = 0; i < bricks.length; i++) {
      var brick = bricks[i];
      if (!brick.alive) {
        continue;
      }

      var nearestX = Math.max(brick.x, Math.min(ball.x, brick.x + brick.w));
      var nearestY = Math.max(brick.y, Math.min(ball.y, brick.y + brick.h));
      var dx = ball.x - nearestX;
      var dy = ball.y - nearestY;

      if (dx * dx + dy * dy > BALL_R * BALL_R) {
        continue;
      }

      if (Math.abs(dx) > Math.abs(dy)) {
        ball.vx = -ball.vx;
      } else {
        ball.vy = -ball.vy;
      }

      brick.alive = false;
      addScore((ROWS - brick.row) * 10);

      // One brick per step keeps a corner hit from reflecting twice.
      return true;
    }

    return false;
  }

  function step() {
    if (!alive) {
      return;
    }

    if (waiting > 0) {
      waiting--;
      ball.x = paddleRatio;
      ball.y = PADDLE_Y - PADDLE_H - BALL_R;
      if (waiting === 0) {
        launch();
      }
      return;
    }

    ball.x += ball.vx;
    ball.y += ball.vy;

    if (ball.x - BALL_R < 0) {
      ball.x = BALL_R;
      ball.vx = Math.abs(ball.vx);
    } else if (ball.x + BALL_R > 1) {
      ball.x = 1 - BALL_R;
      ball.vx = -Math.abs(ball.vx);
    }

    if (ball.y - BALL_R < 0) {
      ball.y = BALL_R;
      ball.vy = Math.abs(ball.vy);
    }

    bounceOffPaddle();
    bounceOffBricks();

    if (!bricksLeft()) {
      nextLevel();
      return;
    }

    if (ball.y - BALL_R > 1) {
      loseLife();
    }
  }

  function draw() {
    var ctx = view.ctx;
    var s = size();

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    // Higher rows are worth more, so they read as the stronger colour.
    ctx.fillStyle = A.theme.accent;
    for (var i = 0; i < bricks.length; i++) {
      var brick = bricks[i];
      if (!brick.alive) {
        continue;
      }
      ctx.globalAlpha = 1 - brick.row * 0.14;
      ctx.fillRect(brick.x * s, brick.y * s, brick.w * s, brick.h * s);
    }
    ctx.globalAlpha = 1;

    ctx.fillStyle = A.theme.fg;
    ctx.fillRect(
      (paddleRatio - PADDLE_W / 2) * s,
      (PADDLE_Y - PADDLE_H) * s,
      PADDLE_W * s,
      PADDLE_H * s
    );

    ctx.beginPath();
    ctx.arc(ball.x * s, ball.y * s, BALL_R * s, 0, Math.PI * 2);
    ctx.fill();
  }

  function movePaddle(ratio) {
    var half = PADDLE_W / 2;
    paddleRatio = Math.min(1 - half, Math.max(half, ratio));
  }

  A.onDrag(stage, movePaddle);

  A.onKeys(function (dir) {
    if (dir === "left") {
      movePaddle(paddleRatio - KEY_NUDGE);
    } else if (dir === "right") {
      movePaddle(paddleRatio + KEY_NUDGE);
    }
  });

  buildBricks();
  updateHint();
  resetBall();

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
