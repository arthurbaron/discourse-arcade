/* Hold the Line for the Discourse arcade. One run, one score: no in-game
 * restart.
 *
 * Fixed shooter. The formation slides sideways and steps down every time it
 * reaches a wall, and it speeds up as you thin it out. Firing is automatic,
 * because tapping a fire button while dragging is not a one-thumb job. The
 * skill lives in positioning instead: only two of your shots fit on screen at
 * once, so a miss costs you tempo while the formation keeps coming.
 */
(function () {
  "use strict";

  var A = window.Arcade;

  var STEP_MS = 16;
  var START_LIVES = 3;

  // Everything is a fraction of the square stage.
  var COLS = 7;
  var MAX_ROWS = 4;
  var ENEMY_W = 0.075;
  var ENEMY_H = 0.055;
  var GAP_X = 0.035;
  var GAP_Y = 0.03;
  var MARGIN = 0.03;
  var STEP_DOWN = 0.035;

  var PLAYER_W = 0.1;
  var PLAYER_H = 0.035;
  var PLAYER_Y = 0.93;
  var KEY_NUDGE = 0.07;

  var SHOT_W = 0.008;
  var SHOT_H = 0.035;
  var SHOT_SPEED = 0.026;
  var MAX_SHOTS = 2;
  var FIRE_EVERY = 12;

  var BOMB_R = 0.012;
  var BOMB_SPEED = 0.0125;

  var RESPAWN_STEPS = 45;

  // Semantic danger colour, deliberately outside the theme so incoming fire
  // never blends into the forum's accent.
  var DANGER = "#d1594a";

  var stage = document.getElementById("stage");
  var view = A.canvas(document.getElementById("view"));
  var scoreEl = document.getElementById("score");
  var hintEl = document.getElementById("hint");
  var overEl = document.getElementById("over");

  var blockWidth = COLS * ENEMY_W + (COLS - 1) * GAP_X;

  var enemies = [];
  var shots = [];
  var bombs = [];
  var formation = { x: MARGIN, y: 0.1, dir: 1 };
  var player = { x: 0.5 };
  var score = 0;
  var lives = START_LIVES;
  var wave = 1;
  var rows = 2;
  var alive = true;
  var fireTimer = 0;
  var bombTimer = 0;
  var respawn = 0;

  function size() {
    return Math.min(view.w, view.h);
  }

  function rowsForWave(n) {
    return Math.min(MAX_ROWS, 1 + Math.ceil(n / 2));
  }

  function buildWave() {
    rows = rowsForWave(wave);
    enemies = [];

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < COLS; col++) {
        enemies.push({ col: col, row: row, alive: true });
      }
    }

    formation.x = MARGIN;
    formation.y = 0.08;
    formation.dir = 1;
    shots = [];
    bombs = [];
    fireTimer = 0;
    bombTimer = 0;
  }

  function aliveCount() {
    var n = 0;
    for (var i = 0; i < enemies.length; i++) {
      if (enemies[i].alive) {
        n++;
      }
    }
    return n;
  }

  // The formation speeds up as it thins out, which is what gives the last few
  // attackers their bite.
  function formationSpeed() {
    var total = enemies.length || 1;
    var left = aliveCount();
    var thinned = 1 + 2.4 * (1 - left / total);
    return 0.0022 * thinned * (1 + 0.16 * (wave - 1));
  }

  function bombInterval() {
    return Math.max(16, 58 - wave * 5);
  }

  function enemyBox(enemy) {
    return {
      x: formation.x + enemy.col * (ENEMY_W + GAP_X),
      y: formation.y + enemy.row * (ENEMY_H + GAP_Y),
      w: ENEMY_W,
      h: ENEMY_H,
    };
  }

  function updateHint() {
    hintEl.innerHTML = "Wave " + wave + " &middot; Lives " + Math.max(0, lives);
  }

  function addScore(points) {
    score += points;
    scoreEl.textContent = String(score);
  }

  function finish(message) {
    alive = false;
    overEl.textContent = message;
    overEl.classList.add("visible");
    A.submit(score);
  }

  function loseLife() {
    lives--;
    updateHint();

    if (lives <= 0) {
      finish("Game over");
      return;
    }

    bombs = [];
    respawn = RESPAWN_STEPS;
  }

  function nextWave() {
    addScore(100 * wave);
    wave++;
    updateHint();
    buildWave();
  }

  function movePlayer(ratio) {
    var half = PLAYER_W / 2;
    player.x = Math.min(1 - half, Math.max(half, ratio));
  }

  function fire() {
    if (shots.length >= MAX_SHOTS) {
      return;
    }
    shots.push({ x: player.x, y: PLAYER_Y - PLAYER_H });
  }

  // A bomb comes from the lowest surviving attacker in a random column, so it
  // always looks like it was dropped by something you can see.
  function dropBomb() {
    var columns = [];

    for (var col = 0; col < COLS; col++) {
      var lowest = null;
      for (var i = 0; i < enemies.length; i++) {
        var enemy = enemies[i];
        if (enemy.alive && enemy.col === col) {
          if (!lowest || enemy.row > lowest.row) {
            lowest = enemy;
          }
        }
      }
      if (lowest) {
        columns.push(lowest);
      }
    }

    if (!columns.length) {
      return;
    }

    var pick = columns[Math.floor(Math.random() * columns.length)];
    var box = enemyBox(pick);
    bombs.push({ x: box.x + box.w / 2, y: box.y + box.h });
  }

  function moveFormation() {
    var speed = formationSpeed();
    formation.x += formation.dir * speed;

    var minX = MARGIN;
    var maxX = 1 - MARGIN - blockWidth;

    if (formation.x <= minX) {
      formation.x = minX;
      formation.dir = 1;
      formation.y += STEP_DOWN;
    } else if (formation.x >= maxX) {
      formation.x = maxX;
      formation.dir = -1;
      formation.y += STEP_DOWN;
    }
  }

  function advanceShots() {
    for (var i = shots.length - 1; i >= 0; i--) {
      var shot = shots[i];
      shot.y -= SHOT_SPEED;

      if (shot.y + SHOT_H < 0) {
        shots.splice(i, 1);
        continue;
      }

      for (var j = 0; j < enemies.length; j++) {
        var enemy = enemies[j];
        if (!enemy.alive) {
          continue;
        }

        var box = enemyBox(enemy);
        var hit =
          shot.x + SHOT_W / 2 > box.x &&
          shot.x - SHOT_W / 2 < box.x + box.w &&
          shot.y < box.y + box.h &&
          shot.y + SHOT_H > box.y;

        if (hit) {
          enemy.alive = false;
          addScore((rows - enemy.row) * 10);
          shots.splice(i, 1);
          break;
        }
      }
    }
  }

  function advanceBombs() {
    var half = PLAYER_W / 2;
    var top = PLAYER_Y - PLAYER_H;

    for (var i = bombs.length - 1; i >= 0; i--) {
      var bomb = bombs[i];
      bomb.y += BOMB_SPEED;

      if (bomb.y - BOMB_R > 1) {
        bombs.splice(i, 1);
        continue;
      }

      if (respawn > 0) {
        continue;
      }

      var hit =
        bomb.y + BOMB_R > top &&
        bomb.y - BOMB_R < PLAYER_Y &&
        bomb.x + BOMB_R > player.x - half &&
        bomb.x - BOMB_R < player.x + half;

      if (hit) {
        bombs.splice(i, 1);
        loseLife();
        return;
      }
    }
  }

  function formationReachedLine() {
    var top = PLAYER_Y - PLAYER_H;

    for (var i = 0; i < enemies.length; i++) {
      if (!enemies[i].alive) {
        continue;
      }
      var box = enemyBox(enemies[i]);
      if (box.y + box.h >= top) {
        return true;
      }
    }

    return false;
  }

  function step() {
    if (!alive) {
      return;
    }

    if (respawn > 0) {
      respawn--;
    }

    moveFormation();

    if (respawn === 0) {
      fireTimer++;
      if (fireTimer >= FIRE_EVERY) {
        fireTimer = 0;
        fire();
      }
    }

    bombTimer++;
    if (bombTimer >= bombInterval()) {
      bombTimer = 0;
      dropBomb();
    }

    advanceShots();
    advanceBombs();

    if (!alive) {
      return;
    }

    if (formationReachedLine()) {
      finish("They got through");
      return;
    }

    if (aliveCount() === 0) {
      nextWave();
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
    var s = size();

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    // Higher rows score more, so they read as the stronger colour. Same
    // language as Breakout.
    ctx.fillStyle = A.theme.accent;
    for (var i = 0; i < enemies.length; i++) {
      var enemy = enemies[i];
      if (!enemy.alive) {
        continue;
      }
      var box = enemyBox(enemy);
      ctx.globalAlpha = 1 - enemy.row * 0.16;
      roundRect(ctx, box.x * s, box.y * s, box.w * s, box.h * s, s * 0.012);
      ctx.fill();
    }
    ctx.globalAlpha = 1;

    // The line you are holding.
    ctx.save();
    ctx.globalAlpha = 0.35;
    ctx.strokeStyle = A.theme.muted;
    ctx.lineWidth = Math.max(1, s * 0.003);
    ctx.beginPath();
    ctx.moveTo(0, (PLAYER_Y - PLAYER_H) * s);
    ctx.lineTo(s, (PLAYER_Y - PLAYER_H) * s);
    ctx.stroke();
    ctx.restore();

    ctx.fillStyle = A.theme.fg;

    for (var k = 0; k < shots.length; k++) {
      ctx.fillRect(
        (shots[k].x - SHOT_W / 2) * s,
        shots[k].y * s,
        SHOT_W * s,
        SHOT_H * s
      );
    }

    // Blink through the respawn pause so it is obvious you were hit.
    var hidden = respawn > 0 && Math.floor(respawn / 6) % 2 === 0;
    if (!hidden) {
      roundRect(
        ctx,
        (player.x - PLAYER_W / 2) * s,
        (PLAYER_Y - PLAYER_H) * s,
        PLAYER_W * s,
        PLAYER_H * s,
        s * 0.008
      );
      ctx.fill();
    }

    ctx.fillStyle = DANGER;
    for (var b = 0; b < bombs.length; b++) {
      ctx.beginPath();
      ctx.arc(bombs[b].x * s, bombs[b].y * s, BOMB_R * s, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  A.onDrag(stage, movePlayer);

  A.onKeys(function (dir) {
    if (dir === "left") {
      movePlayer(player.x - KEY_NUDGE);
    } else if (dir === "right") {
      movePlayer(player.x + KEY_NUDGE);
    }
  });

  buildWave();
  updateHint();

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
