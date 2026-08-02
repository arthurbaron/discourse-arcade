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

  let A = window.Arcade;

  let STEP_MS = 16;
  let START_LIVES = 3;
  let TAU = Math.PI * 2;

  let SHIP_R = 0.026;
  let THRUST = 0.00058;
  let DRAG = 0.9945;
  let MAX_SPEED = 0.0145;
  let TURN_RATE = 0.075;

  let SHOT_SPEED = 0.019;
  let SHOT_LIFE = 52;
  let MAX_SHOTS = 4;
  let FIRE_EVERY = 11;

  // size 3 splits into two 2s, a 2 into two 1s, a 1 is gone.
  let SIZES = {
    3: { r: 0.075, points: 20 },
    2: { r: 0.045, points: 50 },
    1: { r: 0.026, points: 100 },
  };

  // Dying has two stages, and running them off one counter cost you the next
  // life as well. First the ship is away for a fixed beat: not drawn, not
  // moving, and deaf to your finger. Then it is back and briefly cannot be hit,
  // and that is the part that blinks.
  //
  // The wait is deliberately a fixed length rather than "until the middle is
  // clear". The original arcade waited because it had no shield to fall back
  // on; waiting here left players staring at a frozen field for seconds at a
  // time, because the ship does not shoot while it is away, so nothing clears
  // the middle. The shield is what keeps the return fair.
  let RETURN_STEPS = 42;
  let SHIELD_STEPS = 72;
  let SAFE_RADIUS = 0.17;

  let stage = document.getElementById("stage");
  let view = A.canvas(document.getElementById("view"));
  let scoreEl = document.getElementById("score");
  let hintEl = document.getElementById("hint");
  let overEl = document.getElementById("over");

  let ship = {
    x: 0.5,
    y: 0.5,
    vx: 0,
    vy: 0,
    heading: -Math.PI / 2,
    target: -Math.PI / 2,
    thrusting: false,
  };

  let shots = [];
  let rocks = [];
  let score = 0;
  let lives = START_LIVES;
  let wave = 0;
  let alive = true;
  let fireTimer = 0;
  let returning = 0;
  let shield = 0;
  // Picked the moment you die, so the marker can show you where you will be.
  let returnSpot = { x: 0.5, y: 0.5 };
  const keys = A.keysHeld();
  // A tap turns without thrusting, a hold does both. Counted in steps rather
  // than milliseconds so it stays in lockstep with the fixed-step loop.
  const HOLD_STEPS = 10;
  let touching = false;
  let touchSteps = 0;

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
    let d = a - b;
    if (d > 0.5) {
      d -= 1;
    } else if (d < -0.5) {
      d += 1;
    }
    return d;
  }

  function makeShape() {
    let points = [];
    let count = 9;
    for (let i = 0; i < count; i++) {
      points.push(0.72 + Math.random() * 0.42);
    }
    return points;
  }

  function rockSpeed(sizeKey) {
    let base = 0.0021 * (1 + 0.11 * (wave - 1));
    let nimble = sizeKey === 3 ? 1 : sizeKey === 2 ? 1.35 : 1.75;
    return base * nimble;
  }

  function spawnRock(sizeKey, x, y) {
    let angle = Math.random() * TAU;
    let speed = rockSpeed(sizeKey);

    rocks.push({
      x,
      y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      sizeKey,
      r: SIZES[sizeKey].r,
      shape: makeShape(),
      rot: Math.random() * TAU,
      spin: (Math.random() - 0.5) * 0.02,
    });
  }

  function nextWave() {
    wave++;
    let count = Math.min(9, 3 + wave);

    for (let i = 0; i < count; i++) {
      // Keep the opening rocks off the middle so a fresh wave is survivable.
      let x;
      let y;
      let tries = 0;
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
      "Tap to turn, hold to thrust &middot; Lives " + Math.max(0, lives);
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

  // Room around a point, measured to the nearest rock's edge.
  function clearanceAt(x, y) {
    let nearest = 9;

    for (let i = 0; i < rocks.length; i++) {
      let rock = rocks[i];
      let d = Math.hypot(delta(rock.x, x), delta(rock.y, y)) - rock.r;
      if (d < nearest) {
        nearest = d;
      }
    }

    return nearest;
  }

  // The middle, which keeps a return predictable, unless the middle is occupied.
  function chooseReturnSpot() {
    let best = { x: 0.5, y: 0.5 };
    let bestClearance = clearanceAt(0.5, 0.5);

    if (bestClearance >= SAFE_RADIUS) {
      return best;
    }

    // A ring around the middle: close enough to still feel like the middle,
    // wide enough to find a gap when the middle is busy.
    for (let i = 0; i < 8; i++) {
      let angle = (i / 8) * TAU;
      let spot = {
        x: wrap(0.5 + Math.cos(angle) * 0.24),
        y: wrap(0.5 + Math.sin(angle) * 0.24),
      };
      let clearance = clearanceAt(spot.x, spot.y);

      if (clearance > bestClearance) {
        bestClearance = clearance;
        best = spot;
      }
    }

    return best;
  }

  function loseLife() {
    lives--;
    updateHint();

    if (lives <= 0) {
      finish();
      return;
    }

    // The ship leaves the field here and is put back in the middle in comeBack,
    // not now. Placing it early is what let a finger still on the glass fly a
    // ship nobody could see, and become solid again wherever it ended up.
    shots = [];
    returning = RETURN_STEPS;
    shield = 0;
    returnSpot = chooseReturnSpot();
  }

  function comeBack() {
    ship.x = returnSpot.x;
    ship.y = returnSpot.y;
    ship.vx = 0;
    ship.vy = 0;
    ship.heading = -Math.PI / 2;
    ship.target = -Math.PI / 2;
    returning = 0;
    shield = SHIELD_STEPS;
    // A finger that was already down does not count as a hold that built up
    // while the ship was away, so you do not launch the instant you are back.
    touchSteps = 0;
  }

  function turnTowards(current, target) {
    let diff = target - current;
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
    let rock = rocks[index];
    addScore(SIZES[rock.sizeKey].points);
    rocks.splice(index, 1);

    if (rock.sizeKey === 1) {
      return;
    }

    let smaller = rock.sizeKey - 1;
    for (let i = 0; i < 2; i++) {
      spawnRock(smaller, rock.x, rock.y);
    }
  }

  function isThrusting() {
    return (touching && touchSteps > HOLD_STEPS) || keys.has("up");
  }

  function advanceShip() {
    if (touching) {
      touchSteps++;
    }

    // Turning on a held key is applied every step. Nudging the heading once per
    // keydown meant the operating system's repeat delay showed up as a stutter:
    // one turn, a pause, then a rush. Pointer aiming still eases towards the
    // finger, which is what keeps the ship feeling like it has weight.
    let turning = 0;
    if (keys.has("left")) {
      turning -= 1;
    }
    if (keys.has("right")) {
      turning += 1;
    }

    if (turning !== 0) {
      ship.heading += turning * TURN_RATE;
      ship.target = ship.heading;
    } else {
      ship.heading = turnTowards(ship.heading, ship.target);
    }

    if (isThrusting()) {
      ship.vx += Math.cos(ship.heading) * THRUST;
      ship.vy += Math.sin(ship.heading) * THRUST;
    }

    ship.vx *= DRAG;
    ship.vy *= DRAG;

    let speed = Math.hypot(ship.vx, ship.vy);
    if (speed > MAX_SPEED) {
      ship.vx = (ship.vx / speed) * MAX_SPEED;
      ship.vy = (ship.vy / speed) * MAX_SPEED;
    }

    ship.x = wrap(ship.x + ship.vx);
    ship.y = wrap(ship.y + ship.vy);
  }

  function advanceShots() {
    for (let i = shots.length - 1; i >= 0; i--) {
      let shot = shots[i];
      shot.life--;

      if (shot.life <= 0) {
        shots.splice(i, 1);
        continue;
      }

      shot.x = wrap(shot.x + shot.vx);
      shot.y = wrap(shot.y + shot.vy);

      for (let j = rocks.length - 1; j >= 0; j--) {
        let rock = rocks[j];
        let d = Math.hypot(delta(shot.x, rock.x), delta(shot.y, rock.y));

        if (d < rock.r) {
          shots.splice(i, 1);
          splitRock(j);
          break;
        }
      }
    }
  }

  function advanceRocks() {
    for (let i = 0; i < rocks.length; i++) {
      let rock = rocks[i];
      rock.x = wrap(rock.x + rock.vx);
      rock.y = wrap(rock.y + rock.vy);
      rock.rot += rock.spin;
    }
  }

  function checkShipHit() {
    if (shield > 0) {
      return;
    }

    for (let i = 0; i < rocks.length; i++) {
      let rock = rocks[i];
      let d = Math.hypot(delta(ship.x, rock.x), delta(ship.y, rock.y));

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

    // Away from the field. Rocks carry on, the ship does not exist yet, so
    // nothing in here can move it or cost a life.
    if (returning > 0) {
      advanceRocks();
      returning--;

      if (returning === 0) {
        comeBack();
      }

      return;
    }

    if (shield > 0) {
      shield--;
    }

    advanceShip();
    advanceRocks();

    fireTimer++;
    if (fireTimer >= FIRE_EVERY) {
      fireTimer = 0;
      fire();
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
    for (let i = 0; i < rock.shape.length; i++) {
      let angle = rock.rot + (i / rock.shape.length) * TAU;
      let radius = rock.r * rock.shape[i];
      let px = (rock.x + Math.cos(angle) * radius) * s;
      let py = (rock.y + Math.sin(angle) * radius) * s;
      if (i === 0) {
        ctx.moveTo(px, py);
      } else {
        ctx.lineTo(px, py);
      }
    }
    ctx.closePath();
    ctx.stroke();
  }

  function shipOutline(ctx, s, x, y, heading) {
    let left = heading + 2.5;
    let right = heading - 2.5;

    ctx.beginPath();
    ctx.moveTo(
      (x + Math.cos(heading) * SHIP_R * 1.25) * s,
      (y + Math.sin(heading) * SHIP_R * 1.25) * s
    );
    ctx.lineTo(
      (x + Math.cos(left) * SHIP_R) * s,
      (y + Math.sin(left) * SHIP_R) * s
    );
    ctx.lineTo(
      (x + Math.cos(right) * SHIP_R) * s,
      (y + Math.sin(right) * SHIP_R) * s
    );
    ctx.closePath();
    ctx.stroke();
  }

  // A faint outline on the spot the ship will come back to, so the pause reads
  // as the game holding rather than the ship vanishing, and you have the whole
  // wait to see where you are about to be.
  function drawWaitingMarker(ctx, s) {
    ctx.globalAlpha = 0.3;
    shipOutline(ctx, s, returnSpot.x, returnSpot.y, -Math.PI / 2);
    ctx.globalAlpha = 1;
  }

  function drawShip(ctx, s) {
    // Blinking means you cannot be hit yet. It only runs while the shield counts
    // down, and that always counts down, so the ship can never be left hidden.
    if (shield > 0 && Math.floor(shield / 6) % 2 === 0) {
      return;
    }

    shipOutline(ctx, s, ship.x, ship.y, ship.heading);

    if (!isThrusting()) {
      return;
    }

    // A short flame out of the back, so holding reads as thrusting.
    let back = ship.heading + Math.PI;
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
    let ctx = view.ctx;
    let s = size();

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    ctx.lineWidth = Math.max(1.2, s * 0.0035);
    ctx.lineJoin = "round";

    // Outlines rather than fills, which is both the look of the original and
    // the safest thing across light and dark themes.
    ctx.strokeStyle = A.theme.fg;
    for (let i = 0; i < rocks.length; i++) {
      drawRock(ctx, s, rocks[i]);
    }

    ctx.fillStyle = A.theme.fg;
    for (let k = 0; k < shots.length; k++) {
      ctx.beginPath();
      ctx.arc(shots[k].x * s, shots[k].y * s, s * 0.006, 0, TAU);
      ctx.fill();
    }

    // The ship gets the accent so you can always pick yourself out.
    ctx.strokeStyle = A.theme.accent;
    if (returning > 0) {
      drawWaitingMarker(ctx, s);
    } else {
      drawShip(ctx, s);
    }
  }

  function aimAt(point) {
    let s = size();
    let dx = point.x / s - ship.x;
    let dy = point.y / s - ship.y;

    if (Math.hypot(dx, dy) < 0.01) {
      return;
    }

    ship.target = Math.atan2(dy, dx);
  }

  A.onAim(stage, {
    onStart: function (point) {
      // Aim straight away, so even the shortest tap turns the ship. Thrust waits
      // to see whether the finger stays, which is what lets you line up a shot
      // while coasting instead of always accelerating as you turn.
      touching = true;
      touchSteps = 0;
      aimAt(point);
    },
    onMove: function (from, to) {
      aimAt(to);
    },
    onRelease: function () {
      touching = false;
      touchSteps = 0;
    },
    onCancel: function () {
      touching = false;
      touchSteps = 0;
    },
  });

  // Read-only, for the specs, same convention as the other games. A stationary
  // ship auto-fires and shoots away the very rocks that would hit it, so a spec
  // cannot rely on drifting into one; it needs to steer at a real target. This
  // reads state and sets nothing.
  window.Debris = {
    state() {
      return {
        ship: { x: ship.x, y: ship.y, heading: ship.heading },
        thrusting: isThrusting(),
        rocks: rocks.map(function (rock) {
          return { x: rock.x, y: rock.y, r: rock.r };
        }),
        lives,
        // Split so a spec can tell "away and frozen" from "back and protected".
        onField: returning === 0,
        shielded: shield > 0,
        returnSpot: { x: returnSpot.x, y: returnSpot.y },
      };
    },
  };

  updateHint();
  nextWave();

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
