/* Snake for the Discourse arcade. One run, one score: no in-game restart. */
(function () {
  "use strict";

  let A = window.Arcade;

  let GRID = 18;
  let START_MS = 145;
  let MIN_MS = 65;
  let FOOD_POINTS = 10;

  let stage = document.getElementById("stage");
  let view = A.canvas(document.getElementById("view"));
  let scoreEl = document.getElementById("score");
  let overEl = document.getElementById("over");

  let snake = [];
  let dir = { x: 1, y: 0 };
  let pending = [];
  let food = null;
  let score = 0;
  let eaten = 0;
  let alive = true;

  let VECTORS = {
    left: { x: -1, y: 0 },
    right: { x: 1, y: 0 },
    up: { x: 0, y: -1 },
    down: { x: 0, y: 1 },
  };

  function cellKey(x, y) {
    return y * GRID + x;
  }

  function placeFood() {
    let taken = {};
    snake.forEach(function (part) {
      taken[cellKey(part.x, part.y)] = true;
    });

    let free = [];
    for (let y = 0; y < GRID; y++) {
      for (let x = 0; x < GRID; x++) {
        if (!taken[cellKey(x, y)]) {
          free.push({ x, y });
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

    let next = VECTORS[name];
    if (!next) {
      return;
    }

    // Compare against the last queued turn, so a quick double swipe round a
    // corner keeps both halves instead of dropping one.
    let reference = pending.length ? pending[pending.length - 1] : dir;
    let isReverse = next.x === -reference.x && next.y === -reference.y;
    let isSame = next.x === reference.x && next.y === reference.y;

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

    let head = { x: snake[0].x + dir.x, y: snake[0].y + dir.y };

    if (head.x < 0 || head.y < 0 || head.x >= GRID || head.y >= GRID) {
      finish("Game over");
      return;
    }

    let grew = !!food && head.x === food.x && head.y === food.y;

    // Without growth the tail vacates its cell this same step, so moving into
    // the current tail is legal.
    let body = grew ? snake : snake.slice(0, snake.length - 1);
    for (let i = 0; i < body.length; i++) {
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
    let radius = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.arcTo(x + w, y, x + w, y + h, radius);
    ctx.arcTo(x + w, y + h, x, y + h, radius);
    ctx.arcTo(x, y + h, x, y, radius);
    ctx.arcTo(x, y, x + w, y, radius);
    ctx.closePath();
  }

  function draw() {
    let ctx = view.ctx;
    let size = Math.min(view.w, view.h);
    let cell = size / GRID;

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

    for (let i = snake.length - 1; i >= 0; i--) {
      let part = snake[i];
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
