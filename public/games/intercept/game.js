/* Intercept for the Discourse arcade. One run, one score: no in-game restart.
 *
 * The Missile Command shape. Two things carry the whole game:
 *
 *   Ammo is limited per wave, so you cannot tap your way out of trouble. You
 *   have to wait until several missiles line up and take them together.
 *
 *   Your battery sits on the ground and the counter-missile has to fly up
 *   there, so you aim where a missile is going rather than where it is.
 *
 * A destroyed missile explodes in turn, so one good placement can unzip a whole
 * cluster. That chain is where the big scores come from.
 */
(function () {
  "use strict";

  const A = window.Arcade;

  const STEP_MS = 16;
  const GROUND_Y = 0.92;
  const BATTERY_X = 0.5;

  const CITY_COUNT = 6;
  const CITY_W = 0.075;
  const CITY_H = 0.045;

  const INCOMING_BASE_SPEED = 0.0021;
  const INCOMING_SPEED_STEP = 0.00022;
  // Speed is the one knob that cannot rise forever. The counter-missile flies at
  // COUNTER_SPEED from the ground, so once incoming fire approaches that, nothing
  // can be reached in time and the game stops being a game. It is held here and
  // the pressure continues through the knobs below instead.
  const INCOMING_MAX_SPEED = 0.0075;

  const COUNTER_SPEED = 0.017;

  // Grow, hold, then fade. It can destroy anything for as long as it has a
  // radius, which is what makes chains possible.
  const BLAST_R = 0.075;
  const BLAST_GROW = 18;
  const BLAST_HOLD = 10;
  const BLAST_FADE = 14;

  const AMMO_BASE = 12;
  const AMMO_MAX = 20;
  const WAVE_MISSILES_BASE = 6;
  const WAVE_MISSILES_MAX = 24;
  const SPLIT_FROM_WAVE = 3;

  // Reported by players: past a quarter of a million points the game stopped
  // getting harder. It was true, and worse than it looked. Every knob above
  // flattened out early (ammo by wave 8, missiles per wave by 9, spawn gap by 13,
  // speed by 26) while points per kill stayed at 25 x wave, so from wave 27 the
  // waves were identical forever and paid more each time. Endurance, not skill.
  //
  // The second phase fixes that with the knob the game was built around. Its own
  // design note says ammo is what stops you tapping your way out of trouble, so
  // pressure continues as the ratio of targets to shots: missiles keep arriving
  // in greater numbers, more of them split, they arrive closer together, and the
  // magazine slowly shrinks back. Nothing speeds up, so the late game stays
  // readable; it just demands more kills per shot, until no chain can keep up.
  const PHASE_TWO_FROM = 20;
  const LATE_MISSILES_PER_WAVE = 0.75;
  const LATE_MISSILES_MAX = 60;
  const SPLIT_CHANCE_BASE = 0.35;
  const SPLIT_CHANCE_PER_WAVE = 0.02;
  const SPLIT_CHANCE_MAX = 0.9;
  const LATE_GAP_PER_WAVE = 0.25;
  const GAP_MIN = 7;
  const AMMO_DRAIN_PER_WAVE = 0.2;
  const AMMO_FLOOR = 8;

  const POINTS_PER_HIT = 25;
  const CITY_BONUS = 100;

  // A kill is worth more the higher the wave, which is right while the waves are
  // getting harder and wrong the moment they stop. The knobs above run out of
  // room at wave 78 (ammo is the last one to move), so the multiplier stops
  // there too. Past that the game pays a flat rate: you can still climb, but you
  // are no longer paid extra for waves that are not asking more of you. Without
  // this the reported complaint would just move from wave 26 to wave 78.
  //
  // The spec asserts no knob moves after this wave, so retuning the curve
  // without revisiting this number fails the build rather than quietly
  // reintroducing paid endurance.
  const DIFFICULTY_PEAK_WAVE = 78;

  // Incoming fire and explosions are hazards, so they keep a fixed warm colour
  // instead of a theme one, for the same reason the defenders in Dribble are red.
  const DANGER = "#d1594a";
  const BLAST = "#f0b429";

  const stage = document.getElementById("stage");
  const view = A.canvas(document.getElementById("view"));
  const scoreEl = document.getElementById("score");
  const waveEl = document.getElementById("wave");
  const ammoEl = document.getElementById("ammo");
  const overEl = document.getElementById("over");

  let cities = [];
  let incoming = [];
  let counters = [];
  let blasts = [];

  let score = 0;
  let wave = 0;
  let ammo = 0;
  let toSpawn = 0;
  let spawnTimer = 0;
  let alive = true;
  let betweenWaves = 0;

  function size() {
    return Math.min(view.w, view.h);
  }

  // Every knob is a pure function of the wave, so a spec can walk the whole curve
  // without playing a single wave. The wrappers below read the live wave.
  function incomingSpeedAt(w) {
    return Math.min(
      INCOMING_MAX_SPEED,
      INCOMING_BASE_SPEED + (w - 1) * INCOMING_SPEED_STEP
    );
  }

  function spawnGapAt(w) {
    const early = Math.max(14, 52 - w * 3);
    if (w <= PHASE_TWO_FROM) {
      return early;
    }
    // Keeps closing after the early curve bottoms out, so more of the wave is in
    // the air at once. This is crowding, not speed: each missile flies as fast as
    // before, there are simply fewer gaps to pick them off in.
    const late = early - (w - PHASE_TWO_FROM) * LATE_GAP_PER_WAVE;
    return Math.max(GAP_MIN, late);
  }

  function waveMissilesAt(w) {
    const early = Math.min(WAVE_MISSILES_MAX, WAVE_MISSILES_BASE + w * 2);
    if (w <= PHASE_TWO_FROM) {
      return early;
    }
    const late = early + (w - PHASE_TWO_FROM) * LATE_MISSILES_PER_WAVE;
    return Math.min(LATE_MISSILES_MAX, Math.floor(late));
  }

  function waveAmmoAt(w) {
    const early = Math.min(AMMO_MAX, AMMO_BASE + w);
    if (w <= PHASE_TWO_FROM) {
      return early;
    }
    // The magazine gives back what it grew, slowly. Together with the line above
    // this is the whole of phase two: more to shoot at, less to shoot with.
    const late = early - (w - PHASE_TWO_FROM) * AMMO_DRAIN_PER_WAVE;
    return Math.max(AMMO_FLOOR, Math.round(late));
  }

  function splitChanceAt(w) {
    if (w < SPLIT_FROM_WAVE) {
      return 0;
    }
    return Math.min(
      SPLIT_CHANCE_MAX,
      SPLIT_CHANCE_BASE + Math.max(0, w - PHASE_TWO_FROM) * SPLIT_CHANCE_PER_WAVE
    );
  }

  function incomingSpeed() {
    return incomingSpeedAt(wave);
  }

  function spawnGap() {
    return spawnGapAt(wave);
  }

  function waveMissiles() {
    return waveMissilesAt(wave);
  }

  function waveAmmo() {
    return waveAmmoAt(wave);
  }

  function splitChance() {
    return splitChanceAt(wave);
  }

  function buildCities() {
    cities = [];
    const span = 0.8;
    const left = 0.1;
    for (let i = 0; i < CITY_COUNT; i++) {
      cities.push({
        x: left + (span * (i + 0.5)) / CITY_COUNT,
        alive: true,
      });
    }
  }

  function livingCities() {
    return cities.filter((city) => city.alive);
  }

  function updateBar() {
    waveEl.textContent = String(wave);
    ammoEl.textContent = String(ammo);
    ammoEl.classList.toggle("empty", ammo <= 0);
  }

  function addScore(points) {
    score += points;
    scoreEl.textContent = String(score);
  }

  // What one kill is worth right now.
  function hitValueAt(w) {
    return POINTS_PER_HIT * Math.min(w, DIFFICULTY_PEAK_WAVE);
  }

  function finish() {
    alive = false;
    overEl.textContent = "All cities lost";
    overEl.classList.add("visible");
    A.submit(score);
  }

  // ── Waves ────────────────────────────────────────────────

  function nextWave() {
    wave++;
    ammo = waveAmmo();
    toSpawn = waveMissiles();
    spawnTimer = 0;
    updateBar();
  }

  function waveFinished() {
    return (
      toSpawn <= 0 && incoming.length === 0 && counters.length === 0 &&
      blasts.length === 0
    );
  }

  function spawnIncoming(fromX, fromY, splits) {
    const targets = livingCities();
    if (targets.length === 0) {
      return;
    }

    const target = targets[Math.floor(Math.random() * targets.length)];
    const dx = target.x - fromX;
    const dy = GROUND_Y - fromY;
    const distance = Math.hypot(dx, dy) || 1;
    const speed = incomingSpeed();

    incoming.push({
      x: fromX,
      y: fromY,
      fromX,
      fromY,
      vx: (dx / distance) * speed,
      vy: (dy / distance) * speed,
      targetX: target.x,
      // Where it will break into two, if it does.
      splitAt: splits && Math.random() < splitChance()
        ? 0.3 + Math.random() * 0.2
        : null,
    });
  }

  function splitMissile(missile) {
    missile.splitAt = null;
    // One extra warhead, aimed at another city from where the parent is now.
    spawnIncoming(missile.x, missile.y, false);
  }

  // ── Player fire ──────────────────────────────────────────

  function fireAt(point) {
    if (!alive || ammo <= 0 || betweenWaves > 0) {
      return;
    }

    const s = size();
    const tx = point.x / s;
    const ty = point.y / s;

    // No point aiming into the ground.
    if (ty >= GROUND_Y - 0.01) {
      return;
    }

    const dx = tx - BATTERY_X;
    const dy = ty - GROUND_Y;
    const distance = Math.hypot(dx, dy) || 1;

    ammo--;
    updateBar();

    counters.push({
      x: BATTERY_X,
      y: GROUND_Y,
      vx: (dx / distance) * COUNTER_SPEED,
      vy: (dy / distance) * COUNTER_SPEED,
      targetX: tx,
      targetY: ty,
      travelled: 0,
      distance,
    });
  }

  function addBlast(x, y) {
    blasts.push({ x, y, age: 0 });
  }

  function blastRadius(blast) {
    if (blast.age < BLAST_GROW) {
      return BLAST_R * (blast.age / BLAST_GROW);
    }
    if (blast.age < BLAST_GROW + BLAST_HOLD) {
      return BLAST_R;
    }
    const fading = blast.age - BLAST_GROW - BLAST_HOLD;
    return BLAST_R * Math.max(0, 1 - fading / BLAST_FADE);
  }

  // ── Step ─────────────────────────────────────────────────

  function advanceCounters() {
    for (let i = counters.length - 1; i >= 0; i--) {
      const shot = counters[i];
      shot.x += shot.vx;
      shot.y += shot.vy;
      shot.travelled += COUNTER_SPEED;

      if (shot.travelled >= shot.distance) {
        addBlast(shot.targetX, shot.targetY);
        counters.splice(i, 1);
      }
    }
  }

  function advanceIncoming() {
    for (let i = incoming.length - 1; i >= 0; i--) {
      const missile = incoming[i];
      missile.x += missile.vx;
      missile.y += missile.vy;

      if (missile.splitAt !== null && missile.y >= missile.splitAt) {
        splitMissile(missile);
      }

      if (missile.y < GROUND_Y) {
        continue;
      }

      // Landed. Take out whatever city it was aimed at, if it is still there.
      incoming.splice(i, 1);
      addBlast(missile.x, GROUND_Y - CITY_H / 2);

      const hit = cities.find(
        (city) => city.alive && Math.abs(city.x - missile.x) < CITY_W
      );
      if (hit) {
        hit.alive = false;
      }
    }
  }

  function advanceBlasts() {
    for (let i = blasts.length - 1; i >= 0; i--) {
      const blast = blasts[i];
      blast.age++;

      if (blast.age > BLAST_GROW + BLAST_HOLD + BLAST_FADE) {
        blasts.splice(i, 1);
        continue;
      }

      const radius = blastRadius(blast);
      if (radius <= 0) {
        continue;
      }

      // Anything caught in it dies, and explodes in turn. That is the chain.
      for (let j = incoming.length - 1; j >= 0; j--) {
        const missile = incoming[j];
        const d = Math.hypot(missile.x - blast.x, missile.y - blast.y);

        if (d <= radius) {
          incoming.splice(j, 1);
          addScore(hitValueAt(wave));
          addBlast(missile.x, missile.y);
        }
      }
    }
  }

  function step() {
    if (!alive) {
      return;
    }

    if (betweenWaves > 0) {
      betweenWaves--;
      if (betweenWaves === 0) {
        nextWave();
      }
      return;
    }

    if (toSpawn > 0) {
      spawnTimer++;
      if (spawnTimer >= spawnGap()) {
        spawnTimer = 0;
        toSpawn--;
        spawnIncoming(0.06 + Math.random() * 0.88, 0, true);
      }
    }

    advanceCounters();
    advanceIncoming();
    advanceBlasts();

    if (livingCities().length === 0) {
      finish();
      return;
    }

    if (waveFinished()) {
      addScore(CITY_BONUS * livingCities().length);
      betweenWaves = 60;
    }
  }

  // ── Draw ─────────────────────────────────────────────────

  function drawTrail(ctx, s, from, to, colour, width) {
    ctx.strokeStyle = colour;
    ctx.lineWidth = width;
    ctx.beginPath();
    ctx.moveTo(from.x * s, from.y * s);
    ctx.lineTo(to.x * s, to.y * s);
    ctx.stroke();
  }

  function draw() {
    const ctx = view.ctx;
    const s = size();

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    // Ground
    ctx.strokeStyle = A.theme.muted;
    ctx.lineWidth = Math.max(1, s * 0.004);
    ctx.beginPath();
    ctx.moveTo(0, GROUND_Y * s);
    ctx.lineTo(s, GROUND_Y * s);
    ctx.stroke();

    // Cities, and rubble where one used to be.
    cities.forEach((city) => {
      ctx.fillStyle = city.alive ? A.theme.accent : A.theme.muted;
      const height = city.alive ? CITY_H : CITY_H * 0.3;
      ctx.fillRect(
        (city.x - CITY_W / 2) * s,
        (GROUND_Y - height) * s,
        CITY_W * s,
        height * s
      );
    });

    // Battery
    ctx.fillStyle = A.theme.fg;
    ctx.beginPath();
    ctx.moveTo(BATTERY_X * s, (GROUND_Y - 0.05) * s);
    ctx.lineTo((BATTERY_X - 0.03) * s, GROUND_Y * s);
    ctx.lineTo((BATTERY_X + 0.03) * s, GROUND_Y * s);
    ctx.closePath();
    ctx.fill();

    const thin = Math.max(1, s * 0.0035);

    incoming.forEach((missile) => {
      drawTrail(
        ctx,
        s,
        { x: missile.fromX, y: missile.fromY },
        missile,
        DANGER,
        thin
      );
      ctx.fillStyle = DANGER;
      ctx.beginPath();
      ctx.arc(missile.x * s, missile.y * s, s * 0.007, 0, Math.PI * 2);
      ctx.fill();
    });

    counters.forEach((shot) => {
      drawTrail(
        ctx,
        s,
        { x: BATTERY_X, y: GROUND_Y },
        shot,
        A.theme.accent,
        thin
      );
    });

    blasts.forEach((blast) => {
      const radius = blastRadius(blast) * s;
      if (radius <= 0) {
        return;
      }

      ctx.save();
      ctx.globalAlpha = 0.35;
      ctx.fillStyle = BLAST;
      ctx.beginPath();
      ctx.arc(blast.x * s, blast.y * s, radius, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();

      ctx.strokeStyle = BLAST;
      ctx.lineWidth = Math.max(1.5, s * 0.005);
      ctx.beginPath();
      ctx.arc(blast.x * s, blast.y * s, radius, 0, Math.PI * 2);
      ctx.stroke();
    });
  }

  A.onTap(stage, fireAt);

  // Read-only, for the specs, same convention as the other games. A spec cannot
  // aim at a moving dot it cannot see, so it reads the incoming tracks and leads
  // them. Reads state and sets nothing.
  //
  // Shots already in the air and blasts already open are reported too, and that
  // is not padding. Without them nothing outside can tell whether a missile is
  // already dealt with, so any harness double-fires at the same target, runs dry
  // and loses its cities in the second wave. That made the game unmeasurable,
  // which is how a difficulty curve that stops rising at wave 26 went unnoticed
  // until players found it.
  window.Intercept = {
    state() {
      return {
        score,
        wave,
        ammo,
        cities: cities.map((city) => ({ x: city.x, alive: city.alive })),
        incoming: incoming.map((missile) => ({
          x: missile.x,
          y: missile.y,
          vx: missile.vx,
          vy: missile.vy,
          splitAt: missile.splitAt,
        })),
        counters: counters.map((shot) => ({
          x: shot.x,
          y: shot.y,
          targetX: shot.targetX,
          targetY: shot.targetY,
          stepsLeft: Math.max(0, (shot.distance - shot.travelled) / COUNTER_SPEED),
        })),
        openBlasts: blasts.map((blast) => ({
          x: blast.x,
          y: blast.y,
          radius: blastRadius(blast),
        })),
        blasts: blasts.length,
        // The difficulty knobs, so a spec can assert the curve keeps moving
        // rather than infer it from a score.
        curve: {
          incomingSpeed: incomingSpeed(),
          spawnGap: spawnGap(),
          splitChance: splitChance(),
          waveMissiles: waveMissiles(),
          waveAmmo: waveAmmo(),
        },
      };
    },
    rules: {
      incomingSpeed: incomingSpeedAt,
      spawnGap: spawnGapAt,
      splitChance: splitChanceAt,
      waveMissiles: waveMissilesAt,
      waveAmmo: waveAmmoAt,
      hitValue: hitValueAt,
      difficultyPeakWave: () => DIFFICULTY_PEAK_WAVE,
    },
  };

  buildCities();
  nextWave();
  updateBar();

  A.loop(() => STEP_MS, step, draw);
  A.ready();
})();
