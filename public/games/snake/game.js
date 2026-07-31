/* Snake for the Discourse arcade. One run, one score: no in-game restart. */
(function () {
  "use strict";

  var A = window.Arcade;

  var GRID = 18;
  var START_MS = 145;
  var MIN_MS = 65;
  var FOOD_POINTS = 10;

  var stage = document.getElementById("stage");
  var view = A.canvas(document.getElementById("view"));
  var scoreEl = document.getElementById("score");
  var overEl = document.getElementById("over");

  var snake = [];
  var dir = { x: 1, y: 0 };
  var pending = [];
  var food = null;
  var score = 0;
  var eaten = 0;
  var alive = true;

  var VECTORS = {
    left: { x: -1, y: 0 },
    right: { x: 1, y: 0 },
    up: { x: 0, y: -1 },
    down: { x: 0, y: 1 },
  };

  function cellKey(x, y) {
    return y * GRID + x;
  }

  function placeFood() {
    var taken = {};
    snake.forEach(function (part) {
      taken[cellKey(part.x, part.y)] = true;
    });

    var free = [];
    for (var y = 0; y < GRID; y++) {
      for (var x = 0; x < GRID; x++) {
        if (!taken[cellKey(x, y)]) {
          free.push({ x: x, y: y });
        }
      }
    }

    food = free.length ? free[Math.floor(Math.random() * free.length)] : null;
  }

  function start() {
    snake = [
      { x: 8, y: 9 },
      { x: 7, y: 9 },
      { x: 6, y: 9 },
    ];
    dir = { x: 1, y: 0 };
    pending = [];
    score = 0;
    eaten = 0;
    alive = true;
    scoreEl.textContent = "0";
    placeFood();
  }

  function turn(name) {
    if (!alive) {
      return;
    }

    var next = VECTORS[name];
    if (!next) {
      return;
    }

    // Compare against the last queued turn, so a quick double swipe round a
    // corner keeps both halves instead of dropping one.
    var reference = pending.length ? pending[pending.length - 1] : dir;
    var isReverse = next.x === -reference.x && next.y === -reference.y;
    var isSame = next.x === reference.x && next.y === reference.y;

    if (isReverse || isSame) {
      return;
    }

    if (pending.length < 3) {
      pending.push(next);
    }
  }

  function finish(message) {
    alive = false;
    overEl.textContent = message;
    overEl.classList.add("visible");
    A.submit(score);
  }

  function stepMs() {
    return Math.max(MIN_MS, START_MS - eaten * 3);
  }

  function step() {
    if (!alive) {
      return;
    }

    if (pending.length) {
      dir = pending.shift();
    }

    var head = { x: snake[0].x + dir.x, y: snake[0].y + dir.y };

    if (head.x < 0 || head.y < 0 || head.x >= GRID || head.y >= GRID) {
      finish("Game over");
      return;
    }

    var grew = !!food && head.x === food.x && head.y === food.y;

    // Without growth the tail vacates its cell this same step, so moving into
    // the current tail is legal.
    var body = grew ? snake : snake.slice(0, snake.length - 1);
    for (var i = 0; i < body.length; i++) {
      if (body[i].x === head.x && body[i].y === head.y) {
        finish("Game over");
        return;
      }
    }

    snake.unshift(head);

    if (!grew) {
      snake.pop();
      return;
    }

    eaten++;
    score += FOOD_POINTS;
    scoreEl.textContent = String(score);
    placeFood();

    if (!food) {
      finish("Board cleared");
    }
  }

  function roundRect(ctx, x, y, w, h, r) {
    var radius = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.arcTo(x + w, y, x + w, y + h, radius);
    ctx.arcTo(x + w, y + h, x, y + h, radius);
    ctx.arcTo(x, y + h, x, y, radius);
    ctx.arcTo(x, y, x + w, y, radius);
    ctx.closePath();
  }

  function draw() {
    var ctx = view.ctx;
    var size = Math.min(view.w, view.h);
    var cell = size / GRID;

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    if (food) {
      ctx.fillStyle = A.theme.accent;
      ctx.beginPath();
      ctx.arc(
        (food.x + 0.5) * cell,
        (food.y + 0.5) * cell,
        cell * 0.28,
        0,
        Math.PI * 2
      );
      ctx.fill();
    }

    for (var i = snake.length - 1; i >= 0; i--) {
      var part = snake[i];
      ctx.fillStyle = i === 0 ? A.theme.fg : A.theme.muted;
      roundRect(
        ctx,
        part.x * cell + cell * 0.08,
        part.y * cell + cell * 0.08,
        cell * 0.84,
        cell * 0.84,
        cell * 0.24
      );
      ctx.fill();
    }
  }

  A.onSwipe(stage, turn, 18);
  A.onKeys(turn);

  start();
  A.loop(stepMs, step, draw);
  A.ready();
})();
