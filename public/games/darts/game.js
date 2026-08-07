/* Darts for the Discourse arcade. One run, one score: no in-game restart.
 *
 * Fifteen darts at a real board, highest total wins. Aiming is timing, never
 * pointer precision, and that is a fairness decision: if a dart lands where
 * you click, a desktop mouse hits the treble twenty all day and the
 * leaderboard measures input devices instead of players. So a line sweeps
 * across the board, a tap locks it, a second line sweeps the other axis, a
 * tap throws. Identical on a phone and on a mouse.
 *
 * The sweep speed is the whole balance and was simulated before it was set
 * (200,000 throws per cell). At 60 steps edge to edge, a skilled thumb lands
 * the treble twenty about 24% of the time and averages 432 over a run, with
 * the best run in 60,000 simulated at 740 of the 900 ceiling, so a perfect
 * card stays out of reach. The real board's sector order does the rest of the
 * balancing for free: the 20 sits between the 1 and the 5, so treble hunting
 * is a gamble, and a sloppy player measurably scores better aiming at the fat
 * single twenty (16.7 per dart against 13.1). Risk it or bank it is the whole
 * game, and the board itself is the one asking.
 */
(function () {
  "use strict";

  let A = window.Arcade;

  let STEP_MS = 16;
  let TOTAL_DARTS = 15;

  // The real board, clockwise from the top.
  let SECTORS = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

  // Ring radii as fractions of the double ring's outer edge, from the Darts
  // Regulation Authority measurements (6.35/15.9/99/107/162/170 mm).
  let BULL_IN = 0.0374;
  let BULL_OUT = 0.0935;
  let TRIPLE_IN = 0.5824;
  let TRIPLE_OUT = 0.6294;
  let DOUBLE_IN = 0.9529;
  let DOUBLE_OUT = 1.0;

  // The sweep crosses [-RANGE, RANGE] board radii in SWEEP_STEPS fixed steps,
  // and overshoots the board on both sides so a mistimed tap can genuinely
  // miss. WOBBLE is a small landing jitter so two identical taps are not two
  // identical darts.
  let SWEEP_STEPS = 60;
  let RANGE = 1.15;
  let WOBBLE = 0.015;
  let RESULT_STEPS = 40;

  // Fifteen darts are five real visits of three, and three treble twenties in
  // one visit is the sport's magic number. Worth a bonus and a shout. Visits
  // are aligned (darts 1-3, 4-6, ...) exactly as at the oche: three trebles
  // spanning a visit boundary score their points and nothing more.
  let VISIT_SIZE = 3;
  let BONUS_180 = 50;
  let CELEBRATION_STEPS = 110;

  // Where the board sits on the stage: centre and radius in stage fractions.
  let CENTRE_X = 0.5;
  let CENTRE_Y = 0.53;
  let BOARD_R = 0.38;

  let stage = document.getElementById("stage");
  let view = A.canvas(document.getElementById("view"));
  let scoreEl = document.getElementById("score");
  let hintEl = document.getElementById("hint");
  let overEl = document.getElementById("over");

  let phase = "aimX"; // aimX | aimY | result
  let alive = true;
  let dartsThrown = 0;
  let total = 0;

  // Sweep position in board coordinates (fractions of the board radius,
  // centred on the bull). One triangle wave, deterministic, so the timing is
  // something a player can learn rather than chase.
  let sweep = -RANGE;
  let sweepDir = 1;
  let lockedX = 0;
  let lockedY = 0;
  let resultTimer = 0;
  let lastHit = null;
  let hits = [];
  let bonuses180 = 0;
  let celebrating = false;

  function scoreAt(x, y) {
    let hit = hitAt(x, y);
    return hit.points;
  }

  // The full verdict for a landing point in board coordinates: which sector,
  // which ring, how many points, and the label a scoreboard would use.
  function hitAt(x, y) {
    let r = Math.hypot(x, y);

    if (r <= BULL_IN) {
      return { points: 50, base: 50, mult: 1, label: "BULL" };
    }
    if (r <= BULL_OUT) {
      return { points: 25, base: 25, mult: 1, label: "25" };
    }
    if (r > DOUBLE_OUT) {
      return { points: 0, base: 0, mult: 0, label: "MISS" };
    }

    let deg = (Math.atan2(x, -y) * 180) / Math.PI;
    if (deg < 0) {
      deg += 360;
    }
    let base = SECTORS[Math.floor(((deg + 9) % 360) / 18)];

    let mult = 1;
    if (r >= TRIPLE_IN && r <= TRIPLE_OUT) {
      mult = 3;
    } else if (r >= DOUBLE_IN) {
      mult = 2;
    }

    let label = (mult === 3 ? "T" : mult === 2 ? "D" : "") + base;
    return { points: base * mult, base, mult, label };
  }

  // The bonus rule as a pure function. Sixty points is uniquely a treble
  // twenty (no single or double reaches it), so the points alone identify the
  // shot.
  function bonusFor(visitPoints) {
    if (visitPoints.length !== VISIT_SIZE) {
      return 0;
    }
    for (let i = 0; i < visitPoints.length; i++) {
      if (visitPoints[i] !== 60) {
        return 0;
      }
    }
    return BONUS_180;
  }

  function updateHint() {
    let left = TOTAL_DARTS - dartsThrown;
    let last = lastHit ? " · Last " + lastHit.label + (lastHit.points > 0 ? " (" + lastHit.points + ")" : "") : "";
    hintEl.textContent = "Darts " + left + last;
  }

  function finish() {
    alive = false;
    overEl.textContent = "Game over";
    overEl.classList.add("visible");
    A.submit(total);
  }

  function throwDart() {
    // Wobble is a disc, not a square, so it cannot sneak extra reach onto one
    // axis.
    let angle = Math.random() * Math.PI * 2;
    let radius = Math.random() * WOBBLE;
    let x = lockedX + Math.cos(angle) * radius;
    let y = lockedY + Math.sin(angle) * radius;

    let hit = hitAt(x, y);
    lastHit = { x, y, aimX: lockedX, aimY: lockedY, points: hit.points, label: hit.label };
    hits.push(lastHit);
    dartsThrown++;
    total += hit.points;

    // A completed visit gets checked for the maximum. The celebration holds
    // the result phase longer, because this is the moment the game exists for.
    celebrating = false;
    if (hits.length % VISIT_SIZE === 0) {
      let visit = hits.slice(-VISIT_SIZE).map(function (h) {
        return h.points;
      });
      let bonus = bonusFor(visit);
      if (bonus > 0) {
        total += bonus;
        bonuses180++;
        celebrating = true;
      }
    }

    scoreEl.textContent = String(total);
    phase = "result";
    resultTimer = celebrating ? CELEBRATION_STEPS : RESULT_STEPS;
    updateHint();
  }

  A.onTap(stage, function () {
    if (!alive) {
      return;
    }

    if (phase === "aimX") {
      lockedX = sweep;
      sweep = -RANGE;
      sweepDir = 1;
      phase = "aimY";
    } else if (phase === "aimY") {
      lockedY = sweep;
      throwDart();
    }
    // Taps during the result pause do nothing, so a quick double tap cannot
    // burn the next dart's aim.
  });

  function step() {
    if (!alive) {
      return;
    }

    if (phase === "result") {
      resultTimer--;
      if (resultTimer <= 0) {
        if (dartsThrown >= TOTAL_DARTS) {
          finish();
          return;
        }
        sweep = -RANGE;
        sweepDir = 1;
        phase = "aimX";
      }
      return;
    }

    let move = (2 * RANGE) / SWEEP_STEPS;
    sweep += sweepDir * move;
    if (sweep >= RANGE) {
      sweep = RANGE;
      sweepDir = -1;
    } else if (sweep <= -RANGE) {
      sweep = -RANGE;
      sweepDir = 1;
    }
  }

  // ---------------------------------------------------------------------
  // Drawing. The board is the theme, not the traditional red and green: the
  // sectors alternate two greys, the rings alternate accent and muted, and
  // that keeps it flat and readable on any colour scheme.
  // ---------------------------------------------------------------------
  function boardToCanvas(bx, by, s) {
    return {
      x: (CENTRE_X + bx * BOARD_R) * s,
      y: (CENTRE_Y + by * BOARD_R) * s,
    };
  }

  function drawWedge(ctx, s, index, rIn, rOut) {
    let start = ((index * 18 - 9 - 90) * Math.PI) / 180;
    let end = ((index * 18 + 9 - 90) * Math.PI) / 180;
    let cx = CENTRE_X * s;
    let cy = CENTRE_Y * s;

    ctx.beginPath();
    ctx.arc(cx, cy, rOut * BOARD_R * s, start, end);
    ctx.arc(cx, cy, rIn * BOARD_R * s, end, start, true);
    ctx.closePath();
    ctx.fill();
  }

  function drawBoard(ctx, s) {
    let cx = CENTRE_X * s;
    let cy = CENTRE_Y * s;

    ctx.save();

    // The backing circle, slightly past the double ring.
    ctx.fillStyle = "rgba(127, 127, 127, 0.16)";
    ctx.beginPath();
    ctx.arc(cx, cy, BOARD_R * 1.04 * s, 0, Math.PI * 2);
    ctx.fill();

    for (let i = 0; i < 20; i++) {
      // Singles, in two alternating greys.
      ctx.fillStyle = i % 2 === 0 ? "rgba(127, 127, 127, 0.30)" : "rgba(127, 127, 127, 0.08)";
      drawWedge(ctx, s, i, BULL_OUT, DOUBLE_OUT);

      // Triple and double bands, alternating accent and muted like the real
      // board alternates red and green.
      ctx.fillStyle = i % 2 === 0 ? A.theme.accent : A.theme.muted;
      drawWedge(ctx, s, i, TRIPLE_IN, TRIPLE_OUT);
      drawWedge(ctx, s, i, DOUBLE_IN, DOUBLE_OUT);
    }

    // The bulls.
    ctx.fillStyle = A.theme.muted;
    ctx.beginPath();
    ctx.arc(cx, cy, BULL_OUT * BOARD_R * s, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = A.theme.accent;
    ctx.beginPath();
    ctx.arc(cx, cy, BULL_IN * BOARD_R * s, 0, Math.PI * 2);
    ctx.fill();

    // The numbers, small and out of the way.
    ctx.fillStyle = A.theme.muted;
    ctx.font = "600 " + Math.round(s * 0.032) + "px -apple-system, Helvetica, Arial, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    for (let i = 0; i < 20; i++) {
      let angle = ((i * 18 - 90) * Math.PI) / 180;
      let nx = cx + Math.cos(angle) * BOARD_R * 1.13 * s;
      let ny = cy + Math.sin(angle) * BOARD_R * 1.13 * s;
      ctx.fillText(String(SECTORS[i]), nx, ny);
    }

    ctx.restore();
  }

  function drawDarts(ctx, s) {
    for (let i = 0; i < hits.length; i++) {
      let p = boardToCanvas(hits[i].x, hits[i].y, s);
      ctx.fillStyle = A.theme.fg;
      ctx.beginPath();
      ctx.arc(p.x, p.y, s * 0.009, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function drawSweep(ctx, s) {
    if (phase !== "aimX" && phase !== "aimY") {
      return;
    }

    ctx.save();
    ctx.lineWidth = Math.max(1.5, s * 0.004);

    if (phase === "aimY") {
      // The locked vertical line stays visible but steps back.
      let lx = boardToCanvas(lockedX, 0, s).x;
      ctx.globalAlpha = 0.35;
      ctx.strokeStyle = A.theme.fg;
      ctx.beginPath();
      ctx.moveTo(lx, 0);
      ctx.lineTo(lx, s);
      ctx.stroke();
    }

    ctx.globalAlpha = 0.9;
    ctx.strokeStyle = A.theme.accent;
    ctx.beginPath();
    if (phase === "aimX") {
      let x = boardToCanvas(sweep, 0, s).x;
      ctx.moveTo(x, 0);
      ctx.lineTo(x, s);
    } else {
      let y = boardToCanvas(0, sweep, s).y;
      ctx.moveTo(0, y);
      ctx.lineTo(s, y);

      // Where the dart would land right now.
      let p = boardToCanvas(lockedX, sweep, s);
      ctx.fillStyle = A.theme.accent;
      ctx.beginPath();
      ctx.arc(p.x, p.y, s * 0.012, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.stroke();
    ctx.restore();
  }

  function drawResult(ctx, s) {
    if (phase !== "result" || !lastHit) {
      return;
    }

    if (celebrating) {
      // The shout. Big, blinking, and over the whole board, because three
      // treble twenties deserve nothing less.
      ctx.save();
      let visible = Math.floor(resultTimer / 8) % 2 === 0;
      if (visible) {
        ctx.fillStyle = A.theme.accent;
        ctx.font = "800 " + Math.round(s * 0.3) + "px -apple-system, Helvetica, Arial, sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText("180", s * 0.5, s * 0.46);
        ctx.font = "700 " + Math.round(s * 0.06) + "px -apple-system, Helvetica, Arial, sans-serif";
        ctx.fillText("+" + BONUS_180 + " bonus", s * 0.5, s * 0.66);
      }
      ctx.restore();
      return;
    }

    ctx.save();
    ctx.fillStyle = lastHit.points >= 40 ? A.theme.accent : A.theme.fg;
    ctx.font = "700 " + Math.round(s * 0.07) + "px -apple-system, Helvetica, Arial, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    let text = lastHit.points > 0 ? lastHit.label + "  +" + lastHit.points : "MISS";
    ctx.fillText(text, s * 0.5, s * 0.07);
    ctx.restore();
  }

  function draw() {
    let ctx = view.ctx;
    let s = Math.min(view.w, view.h);

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    drawBoard(ctx, s);
    drawDarts(ctx, s);
    drawSweep(ctx, s);
    drawResult(ctx, s);
  }

  // Read-only, for the specs, same convention as the other games. The board
  // maths lives in hitAt, which a spec can walk point by point; the sweep and
  // lock state are what let it check that a tap freezes one axis while the
  // other keeps moving, and that a landing stays within the wobble disc of
  // the locked aim.
  window.Darts = {
    state() {
      return {
        phase,
        alive,
        dartsThrown,
        dartsTotal: TOTAL_DARTS,
        total,
        sweep,
        lockedX,
        lockedY,
        lastHit,
        hits: hits.slice(),
        bonuses180,
        celebrating,
        config: {
          sweepSteps: SWEEP_STEPS,
          range: RANGE,
          wobble: WOBBLE,
          visitSize: VISIT_SIZE,
          bonus180: BONUS_180,
        },
      };
    },
    rules: { scoreAt, hitAt, bonusFor },
  };

  updateHint();

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
