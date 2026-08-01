/* Debris for the Discourse arcade. One run, one score: no in-game restart.
 *
 * The Asteroids shape, with the controls rebuilt for a thumb. Classic rotate
 * and thrust buttons are unusable on a touchscreen, so instead the ship turns
 * towards wherever your finger is and thrusts while you hold. Crucially it
 * turns at a limited rate rather than snapping, so this is still a fight with
 * your own momentum and not a twin-stick shooter. Let go and you keep drifting.
 *
 * Arrow keys keep the classic scheme for anyone on a keyboard.
 */
(function () {
  "use strict";

  var A = window.Arcade;

  var STEP_MS = 16;
  var START_LIVES = 3;
  var TAU = Math.PI * 2;

  var SHIP_R = 0.026;
  var THRUST = 0.00058;
  var DRAG = 0.9945;
  var MAX_SPEED = 0.0145;
  var TURN_RATE = 0.075;
  var KEY_THRUST_STEPS = 8;

  var SHOT_SPEED = 0.019;
  var SHOT_LIFE = 52;
  var MAX_SHOTS = 4;
  var FIRE_EVERY = 11;

  // size 3 splits into two 2s, a 2 into two 1s, a 1 is gone.
  var SIZES = {
    3: { r: 0.075, points: 20 },
    2: { r: 0.045, points: 50 },
    1: { r: 0.026, points: 100 },
  };

  var RESPAWN_STEPS = 70;
  var SAFE_RADIUS = 0.17;

  var stage = document.getElementById("stage");
  var view = A.canvas(document.getElementById("view"));
  var scoreEl = document.getElementById("score");
  var hintEl = document.getElementById("hint");
  var overEl = document.getElementById("over");

  var ship = {
    x: 0.5,
    y: 0.5,
    vx: 0,
    vy: 0,
    heading: -Math.PI / 2,
    target: -Math.PI / 2,
    thrusting: false,
  };

  var shots = [];
  var rocks = [];
  var score = 0;
  var lives = START_LIVES;
  var wave = 0;
  var alive = true;
  var fireTimer = 0;
  var respawn = 0;
  var keyThrust = 0;

  function size() {
    return Math.min(view.w, view.h);
  }

  function wrap(value) {
    if (value < 0) {
      return value + 1;
    }
    if (value > 1) {
      return value - 1;
    }
    return value;
  }

  // Shortest distance on a wrapping field, so a rock just over the edge is
  // still close.
  function delta(a, b) {
    var d = a - b;
    if (d > 0.5) {
      d -= 1;
    } else if (d < -0.5) {
      d += 1;
    }
    return d;
  }

  function makeShape() {
    var points = [];
    var count = 9;
    for (var i = 0; i < count; i++) {
      points.push(0.72 + Math.random() * 0.42);
    }
    return points;
  }

  function rockSpeed(sizeKey) {
    var base = 0.0021 * (1 + 0.11 * (wave - 1));
    var nimble = sizeKey === 3 ? 1 : sizeKey === 2 ? 1.35 : 1.75;
    return base * nimble;
  }

  function spawnRock(sizeKey, x, y) {
    var angle = Math.random() * TAU;
    var speed = rockSpeed(sizeKey);

    rocks.push({
      x: x,
      y: y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      sizeKey: sizeKey,
      r: SIZES[sizeKey].r,
      shape: makeShape(),
      rot: Math.random() * TAU,
      spin: (Math.random() - 0.5) * 0.02,
    });
  }

  function nextWave() {
    wave++;
    var count = Math.min(9, 3 + wave);

    for (var i = 0; i < count; i++) {
      // Keep the opening rocks off the middle so a fresh wave is survivable.
      var x;
      var y;
      var tries = 0;
      do {
        x = Math.random();
        y = Math.random();
        tries++;
      } while (
        Math.hypot(delta(x, ship.x), delta(y, ship.y)) < 0.26 &&
        tries < 40
      );

      spawnRock(3, x, y);
    }

    updateHint();
  }

  function updateHint() {
    hintEl.innerHTML =
      "Hold to steer and thrust &middot; Lives " + Math.max(0, lives);
  }

  function addScore(points) {
    score += points;
    scoreEl.textContent = String(score);
  }

  function finish() {
    alive = false;
    overEl.textContent = "Game over";
    overEl.classList.add("visible");
    A.submit(score);
  }

  function centreIsClear() {
    for (var i = 0; i < rocks.length; i++) {
      var rock = rocks[i];
      var d = Math.hypot(delta(rock.x, 0.5), delta(rock.y, 0.5));
      if (d < SAFE_RADIUS + rock.r) {
        return false;
      }
    }
    return true;
  }

  function loseLife() {
    lives--;
    updateHint();

    if (lives <= 0) {
      finish();
      return;
    }

    ship.x = 0.5;
    ship.y = 0.5;
    ship.vx = 0;
    ship.vy = 0;
    ship.heading = -Math.PI / 2;
    ship.target = -Math.PI / 2;
    ship.thrusting = false;
    shots = [];
    respawn = RESPAWN_STEPS;
  }

  function turnTowards(current, target) {
    var diff = target - current;
    while (diff > Math.PI) {
      diff -= TAU;
    }
    while (diff < -Math.PI) {
      diff += TAU;
    }
    if (Math.abs(diff) <= TURN_RATE) {
      return target;
    }
    return current + Math.sign(diff) * TURN_RATE;
  }

  function fire() {
    if (shots.length >= MAX_SHOTS) {
      return;
    }

    shots.push({
      x: ship.x + Math.cos(ship.heading) * SHIP_R,
      y: ship.y + Math.sin(ship.heading) * SHIP_R,
      vx: ship.vx + Math.cos(ship.heading) * SHOT_SPEED,
      vy: ship.vy + Math.sin(ship.heading) * SHOT_SPEED,
      life: SHOT_LIFE,
    });
  }

  function splitRock(index) {
    var rock = rocks[index];
    addScore(SIZES[rock.sizeKey].points);
    rocks.splice(index, 1);

    if (rock.sizeKey === 1) {
      return;
    }

    var smaller = rock.sizeKey - 1;
    for (var i = 0; i < 2; i++) {
      spawnRock(smaller, rock.x, rock.y);
    }
  }

  function advanceShip() {
    ship.heading = turnTowards(ship.heading, ship.target);

    if (keyThrust > 0) {
      keyThrust--;
    }

    if (ship.thrusting || keyThrust > 0) {
      ship.vx += Math.cos(ship.heading) * THRUST;
      ship.vy += Math.sin(ship.heading) * THRUST;
    }

    ship.vx *= DRAG;
    ship.vy *= DRAG;

    var speed = Math.hypot(ship.vx, ship.vy);
    if (speed > MAX_SPEED) {
      ship.vx = (ship.vx / speed) * MAX_SPEED;
      ship.vy = (ship.vy / speed) * MAX_SPEED;
    }

    ship.x = wrap(ship.x + ship.vx);
    ship.y = wrap(ship.y + ship.vy);
  }

  function advanceShots() {
    for (var i = shots.length - 1; i >= 0; i--) {
      var shot = shots[i];
      shot.life--;

      if (shot.life <= 0) {
        shots.splice(i, 1);
        continue;
      }

      shot.x = wrap(shot.x + shot.vx);
      shot.y = wrap(shot.y + shot.vy);

      for (var j = rocks.length - 1; j >= 0; j--) {
        var rock = rocks[j];
        var d = Math.hypot(delta(shot.x, rock.x), delta(shot.y, rock.y));

        if (d < rock.r) {
          shots.splice(i, 1);
          splitRock(j);
          break;
        }
      }
    }
  }

  function advanceRocks() {
    for (var i = 0; i < rocks.length; i++) {
      var rock = rocks[i];
      rock.x = wrap(rock.x + rock.vx);
      rock.y = wrap(rock.y + rock.vy);
      rock.rot += rock.spin;
    }
  }

  function checkShipHit() {
    if (respawn > 0) {
      return;
    }

    for (var i = 0; i < rocks.length; i++) {
      var rock = rocks[i];
      var d = Math.hypot(delta(ship.x, rock.x), delta(ship.y, rock.y));

      if (d < rock.r + SHIP_R * 0.75) {
        loseLife();
        return;
      }
    }
  }

  function step() {
    if (!alive) {
      return;
    }

    if (respawn > 0) {
      // Classic behaviour: you do not come back until the middle is safe.
      if (respawn > 1 || centreIsClear()) {
        respawn--;
      }
    }

    advanceShip();
    advanceRocks();

    if (respawn === 0) {
      fireTimer++;
      if (fireTimer >= FIRE_EVERY) {
        fireTimer = 0;
        fire();
      }
    }

    advanceShots();
    checkShipHit();

    if (!alive) {
      return;
    }

    if (rocks.length === 0) {
      nextWave();
    }
  }

  function drawRock(ctx, s, rock) {
    ctx.beginPath();
    for (var i = 0; i < rock.shape.length; i++) {
      var angle = rock.rot + (i / rock.shape.length) * TAU;
      var radius = rock.r * rock.shape[i];
      var px = (rock.x + Math.cos(angle) * radius) * s;
      var py = (rock.y + Math.sin(angle) * radius) * s;
      if (i === 0) {
        ctx.moveTo(px, py);
      } else {
        ctx.lineTo(px, py);
      }
    }
    ctx.closePath();
    ctx.stroke();
  }

  function drawShip(ctx, s) {
    var hidden = respawn > 0 && Math.floor(respawn / 6) % 2 === 0;
    if (hidden) {
      return;
    }

    var nose = ship.heading;
    var left = ship.heading + 2.5;
    var right = ship.heading - 2.5;

    ctx.beginPath();
    ctx.moveTo(
      (ship.x + Math.cos(nose) * SHIP_R * 1.25) * s,
      (ship.y + Math.sin(nose) * SHIP_R * 1.25) * s
    );
    ctx.lineTo(
      (ship.x + Math.cos(left) * SHIP_R) * s,
      (ship.y + Math.sin(left) * SHIP_R) * s
    );
    ctx.lineTo(
      (ship.x + Math.cos(right) * SHIP_R) * s,
      (ship.y + Math.sin(right) * SHIP_R) * s
    );
    ctx.closePath();
    ctx.stroke();

    if (!ship.thrusting && keyThrust <= 0) {
      return;
    }

    // A short flame out of the back, so holding reads as thrusting.
    var back = ship.heading + Math.PI;
    ctx.beginPath();
    ctx.moveTo(
      (ship.x + Math.cos(back) * SHIP_R * 0.6) * s,
      (ship.y + Math.sin(back) * SHIP_R * 0.6) * s
    );
    ctx.lineTo(
      (ship.x + Math.cos(back) * SHIP_R * 1.5) * s,
      (ship.y + Math.sin(back) * SHIP_R * 1.5) * s
    );
    ctx.stroke();
  }

  function draw() {
    var ctx = view.ctx;
    var s = size();

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    ctx.lineWidth = Math.max(1.2, s * 0.0035);
    ctx.lineJoin = "round";

    // Outlines rather than fills, which is both the look of the original and
    // the safest thing across light and dark themes.
    ctx.strokeStyle = A.theme.fg;
    for (var i = 0; i < rocks.length; i++) {
      drawRock(ctx, s, rocks[i]);
    }

    ctx.fillStyle = A.theme.fg;
    for (var k = 0; k < shots.length; k++) {
      ctx.beginPath();
      ctx.arc(shots[k].x * s, shots[k].y * s, s * 0.006, 0, TAU);
      ctx.fill();
    }

    // The ship gets the accent so you can always pick yourself out.
    ctx.strokeStyle = A.theme.accent;
    drawShip(ctx, s);
  }

  function aimAt(point) {
    var s = size();
    var dx = point.x / s - ship.x;
    var dy = point.y / s - ship.y;

    if (Math.hypot(dx, dy) < 0.01) {
      return;
    }

    ship.target = Math.atan2(dy, dx);
  }

  A.onAim(stage, {
    onStart: function (point) {
      ship.thrusting = true;
      aimAt(point);
    },
    onMove: function (from, to) {
      aimAt(to);
    },
    onRelease: function () {
      ship.thrusting = false;
    },
    onCancel: function () {
      ship.thrusting = false;
    },
  });

  A.onKeys(function (dir) {
    if (dir === "left") {
      ship.target = ship.heading - TURN_RATE * 3;
    } else if (dir === "right") {
      ship.target = ship.heading + TURN_RATE * 3;
    } else if (dir === "up") {
      keyThrust = KEY_THRUST_STEPS;
    }
  });

  updateHint();
  nextWave();

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
