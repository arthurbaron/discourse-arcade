/* Stack for the Discourse arcade. One run, one score: no in-game restart.
 *
 * A slab slides across the top of a tower, a tap drops it, and whatever hangs
 * over the slab below is sliced away. What survives is the width the next slab
 * gets, so a perfect drop costs nothing and a sloppy one costs you forever.
 * Score is the number of layers standing.
 *
 * The whole design rests on one number: the forgiveness margin, the small
 * slack within which a near-perfect drop snaps into place and loses nothing.
 * Without it the game is joyless, since every layer sheds a sliver no matter
 * how well you play. With a FIXED one it has no ceiling at all: simulated, an
 * expert-level player ran into the 5,000 layer runaway guard, which is exactly
 * the wall-versus-no-wall problem Penalty and Debris each taught in their own
 * way.
 *
 * So the margin shrinks with height and reaches zero at layer 13. Forgiving
 * while you learn, unforgiving once you are good, and the run always ends.
 * The sweep speed was slowed to 80% of its original pace on request, which
 * gives everyone a little more room to read the board: measured over 40,000
 * simulated runs per skill level, an expert now averages 54 layers with a
 * best of 71, a decent player 34, a casual one 20.
 *
 * That still leaves a script with no timing error at all, which no amount of
 * margin decay would stop. It stops itself: the slab moves in discrete steps,
 * so the positions it can occupy form a grid, and once the margin is gone the
 * closest reachable position is still half a step off centre. A perfect
 * tap-bot, driven against the real game rather than a model of it, dies at
 * layer 161. Measured directly rather than assumed: an earlier hand-derived
 * estimate of 92 for the pre-slowdown speed turned out to be wrong when
 * actually run, and the true figure (147) left only 3 layers of headroom
 * under the plausibility ceiling below. Worth remembering that a model of the
 * game is not the game.
 */
(function () {
  "use strict";

  let A = window.Arcade;

  let STEP_MS = 16;

  // Everything is a fraction of the square board.
  let START_W = 0.62;
  let MIN_W = 0.035;
  let SLAB_H = 0.042;

  // The slab sweeps the full board and speeds up as you climb. Slowed to 80%
  // of the original pace on request: easier to read, a bit more forgiving,
  // and simulated to still end every run comfortably under the plausibility
  // ceiling below.
  let SPEED_START = 0.0088;
  let SPEED_PER_LAYER = 0.00028;
  let SPEED_MAX = 0.024;

  // The forgiveness margin, as a fraction of the current slab's width. Started
  // at 14% decaying 0.006, and that was reported from play as too soft: a
  // skilled player stacked a median of nineteen layers without shedding a
  // single sliver, which is more than fit on screen, so the tower never looked
  // like a tower. Tightening to 9% halves the free ride to ten layers, which
  // means the narrowing starts before the tower fills the board, and barely
  // touches run length (expert mean 52 to 47). Worth measuring the free-layer
  // count on its own: run length alone would have said nothing was wrong.
  let MARGIN_START = 0.09;
  let MARGIN_DECAY = 0.007;

  // The first slab sits on the floor of the board and the tower genuinely grows
  // upward from there. Only once its top reaches ACTION_Y does the camera take
  // over and push everything down to hold it there, so the opening reads as a
  // tower rising rather than as a strip already floating mid-board. That is
  // around fifteen layers of real growth before anything scrolls.
  let BASE_Y = 0.955;
  let ACTION_Y = 0.34;
  let SLIDE_STEPS = 7;

  let PERFECT_STEPS = 26;
  let OVER_STEPS = 16;

  // Purely decorative: something drifts through the empty sky above the
  // action line as you climb, changing with height so the milestone is felt
  // as well as counted. All of it lives above ACTION_Y, which the tower never
  // reaches, so it can never overlap the game itself.
  let SKY_STAGES = [
    { type: "bird", until: 14, y: 0.16, w: 0.032, speed: 0.0035 },
    { type: "plane", until: 34, y: 0.1, w: 0.09, speed: 0.006 },
    { type: "satellite", until: 59, y: 0.05, w: 0.05, speed: 0.0032 },
    { type: "ufo", until: Infinity, y: 0.08, w: 0.075, speed: 0.005 },
  ];
  let SPACE_FROM = 35; // stars appear once the sky reaches the satellite stage
  let flyer = null; // { type, x, y, w, speed }
  let flyerWait = 90;
  let stars = null;

  let stage = document.getElementById("stage");
  let view = A.canvas(document.getElementById("view"));
  let scoreEl = document.getElementById("score");
  let hintEl = document.getElementById("hint");
  let overEl = document.getElementById("over");

  let alive = true;
  let layers = 0;
  let perfectRun = 0;
  let bestPerfectRun = 0;

  // The tower, bottom first. Only the top few are ever drawn.
  let tower = [];
  let slab = null; // the one sliding: { x, w, dir }
  let scraps = []; // sliced-off pieces, falling away
  let perfectFlash = 0;
  let slide = 0; // camera easing after a placement
  let ending = 0;

  function speedAt(layer) {
    return Math.min(SPEED_MAX, SPEED_START + layer * SPEED_PER_LAYER);
  }

  // Zero from layer 13 on, so past that even a flawless human drop shaves
  // something off and the run is guaranteed to end.
  function marginAt(layer, width) {
    return width * Math.max(0, MARGIN_START - layer * MARGIN_DECAY);
  }

  // The heart of the game, as a pure function so a spec can walk it without
  // touching the DOM: given where the slab landed and where the one below sits,
  // what survives?
  function sliceFor(landedX, belowX, width, layer) {
    let miss = Math.abs(landedX - belowX);
    let margin = marginAt(layer, width);

    if (miss <= margin) {
      // Close enough: it snaps square onto the one below and loses nothing.
      return { snapped: true, miss, margin, width, centre: belowX, lost: 0 };
    }

    let left = Math.max(landedX - width / 2, belowX - width / 2);
    let right = Math.min(landedX + width / 2, belowX + width / 2);
    let overlap = right - left;

    return {
      snapped: false,
      miss,
      margin,
      width: Math.max(0, overlap),
      centre: (left + right) / 2,
      lost: width - Math.max(0, overlap),
      scrapCentre: landedX < belowX ? left - (width - overlap) / 2 : right + (width - overlap) / 2,
    };
  }

  function topSlab() {
    return tower[tower.length - 1];
  }

  function skyStageFor(layer) {
    for (let i = 0; i < SKY_STAGES.length; i++) {
      if (layer < SKY_STAGES[i].until) {
        return SKY_STAGES[i];
      }
    }
    return SKY_STAGES[SKY_STAGES.length - 1];
  }

  // Generated once, on first use, and kept: a fixed scatter reads as a sky,
  // one that reshuffles every frame reads as static.
  function ensureStars() {
    if (!stars) {
      stars = [];
      for (let i = 0; i < 16; i++) {
        stars.push({ x: Math.random(), y: 0.02 + Math.random() * 0.28 });
      }
    }
    return stars;
  }

  function spawnFlyer() {
    let sky = skyStageFor(layers);
    flyer = { type: sky.type, x: -sky.w, y: sky.y, w: sky.w, speed: sky.speed };
  }

  function updateHint() {
    let streak = perfectRun > 1 ? " · " + perfectRun + " perfect in a row" : "";
    hintEl.textContent = "Tap to drop" + streak;
  }

  function nextSlab() {
    let top = topSlab();
    // Alternate the side it enters from, so the rhythm never becomes one
    // memorised beat.
    let fromLeft = layers % 2 === 0;
    slab = {
      x: fromLeft ? top.w / 2 : 1 - top.w / 2,
      w: top.w,
      dir: fromLeft ? 1 : -1,
    };
  }

  function finish() {
    alive = false;
    overEl.textContent = "Game over";
    overEl.classList.add("visible");
    A.submit(layers);
  }

  function drop() {
    if (!alive || !slab || ending > 0) {
      return;
    }

    let below = topSlab();
    let result = sliceFor(slab.x, below.x, slab.w, layers);

    // Scraps fall from wherever the slab visually was, which moves once the
    // camera engages, so this is read rather than hardcoded.
    let cutY = towerTopFraction() - SLAB_H;

    if (result.width < MIN_W) {
      // Nothing left to stand on. The slab falls past the tower and that is
      // the run.
      scraps.push({ x: slab.x, w: slab.w, y: cutY, vy: 0 });
      slab = null;
      ending = OVER_STEPS;
      return;
    }

    if (result.snapped) {
      perfectRun++;
      bestPerfectRun = Math.max(bestPerfectRun, perfectRun);
      perfectFlash = PERFECT_STEPS;
    } else {
      perfectRun = 0;
      scraps.push({ x: result.scrapCentre, w: result.lost, y: cutY, vy: 0 });
    }

    tower.push({ x: result.centre, w: result.width });
    layers++;
    scoreEl.textContent = String(layers);
    slide = SLIDE_STEPS;
    updateHint();
    nextSlab();
  }

  A.onTap(stage, drop);

  function step() {
    if (!alive) {
      return;
    }

    // Scraps keep falling whatever else is happening.
    for (let i = scraps.length - 1; i >= 0; i--) {
      let s = scraps[i];
      s.vy += 0.0022;
      s.y += s.vy;
      if (s.y > 1.2) {
        scraps.splice(i, 1);
      }
    }

    // The sky drifts regardless of what else is happening, same as the scraps.
    if (flyer) {
      flyer.x += flyer.speed;
      if (flyer.x > 1 + flyer.w) {
        flyer = null;
        flyerWait = 260 + Math.random() * 260;
      }
    } else {
      flyerWait--;
      if (flyerWait <= 0) {
        spawnFlyer();
      }
    }

    if (ending > 0) {
      ending--;
      if (ending === 0) {
        finish();
      }
      return;
    }

    if (perfectFlash > 0) {
      perfectFlash--;
    }
    if (slide > 0) {
      slide--;
    }

    if (!slab) {
      return;
    }

    let speed = speedAt(layers);
    slab.x += slab.dir * speed;

    // It bounces off the edges rather than wrapping, so the slab is always
    // somewhere a player can read.
    let half = slab.w / 2;
    if (slab.x <= half) {
      slab.x = half;
      slab.dir = 1;
    } else if (slab.x >= 1 - half) {
      slab.x = 1 - half;
      slab.dir = -1;
    }
  }

  // ---------------------------------------------------------------------
  // Drawing. The tower is drawn from the top down and stops once it leaves the
  // board, so a hundred layers costs the same as ten.
  // ---------------------------------------------------------------------
  // How far the whole tower has to be pushed down to keep its top at ACTION_Y.
  // Zero while the tower is still shorter than that, which is what lets the
  // opening layers stack on the floor without the view moving at all.
  function cameraOffset() {
    let eased = slide > 0 ? slide / SLIDE_STEPS : 0;
    let grownLayers = tower.length - 1 - eased;
    let naturalTop = BASE_Y - grownLayers * SLAB_H;
    return Math.max(0, ACTION_Y - naturalTop);
  }

  // Slabs are anchored to the base, not to the top, so during the growth phase
  // the ones already placed do not budge.
  function slabY(indexFromBottom, s) {
    return (BASE_Y - indexFromBottom * SLAB_H + cameraOffset()) * s;
  }

  // Where the top of the tower currently sits, as a board fraction, which is
  // what the sliding slab, its guide line and any freshly cut scrap all hang
  // off.
  function towerTopFraction() {
    return BASE_Y - (tower.length - 1) * SLAB_H + cameraOffset();
  }

  function towerTopY(s) {
    return towerTopFraction() * s;
  }

  function drawSlab(ctx, s, x, y, w, fill, alpha) {
    ctx.save();
    ctx.globalAlpha = alpha === undefined ? 1 : alpha;
    ctx.fillStyle = fill;
    ctx.fillRect((x - w / 2) * s, y, w * s, SLAB_H * s * 0.92);
    ctx.restore();
  }

  // Small and plain on purpose: a silhouette you read at a glance, not an
  // illustration. Everything shares the tower's muted tone, so it always
  // stays background.
  function drawFlyer(ctx, s, f) {
    let x = f.x * s;
    let y = f.y * s;
    let w = f.w * s;

    ctx.save();
    ctx.globalAlpha = 0.6;
    ctx.strokeStyle = A.theme.muted;
    ctx.fillStyle = A.theme.muted;
    ctx.lineWidth = Math.max(1, s * 0.0022);

    if (f.type === "bird") {
      // A shallow double-chevron: the classic distant-bird silhouette, two
      // wingbeats wide.
      ctx.beginPath();
      ctx.moveTo(x - w / 2, y);
      ctx.quadraticCurveTo(x - w / 4, y - w * 0.55, x, y);
      ctx.quadraticCurveTo(x + w / 4, y - w * 0.55, x + w / 2, y);
      ctx.stroke();
    } else if (f.type === "plane") {
      // A fuselage line with a wide wing near the nose and a smaller tail
      // near the back, so it reads as a plane rather than a plain cross.
      ctx.beginPath();
      ctx.moveTo(x - w / 2, y);
      ctx.lineTo(x + w / 2, y);
      ctx.moveTo(x + w * 0.1, y - w * 0.22);
      ctx.lineTo(x + w * 0.1, y + w * 0.22);
      ctx.moveTo(x - w * 0.36, y - w * 0.1);
      ctx.lineTo(x - w * 0.36, y + w * 0.1);
      ctx.stroke();
    } else if (f.type === "satellite") {
      // A small body with a solar panel on each side.
      ctx.fillRect(x - w * 0.12, y - w * 0.12, w * 0.24, w * 0.24);
      ctx.fillRect(x - w / 2, y - w * 0.04, w * 0.3, w * 0.08);
      ctx.fillRect(x + w * 0.2, y - w * 0.04, w * 0.3, w * 0.08);
    } else if (f.type === "ufo") {
      // A flat saucer with a shallow dome on top.
      ctx.beginPath();
      ctx.ellipse(x, y, w / 2, w * 0.16, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.ellipse(x, y - w * 0.1, w * 0.22, w * 0.14, 0, Math.PI, 0);
      ctx.stroke();
    }
    ctx.restore();
  }

  function draw() {
    let ctx = view.ctx;
    let s = Math.min(view.w, view.h);

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    // The sky sits behind everything else. Stars only once the flyers reach
    // the satellite stage, so "far enough up" reads as a change of scene, not
    // just another sprite.
    if (layers >= SPACE_FROM) {
      ctx.save();
      ctx.globalAlpha = 0.5;
      ctx.fillStyle = A.theme.muted;
      let dots = ensureStars();
      for (let i = 0; i < dots.length; i++) {
        ctx.fillRect(dots[i].x * s, dots[i].y * s, Math.max(1, s * 0.0026), Math.max(1, s * 0.0026));
      }
      ctx.restore();
    }
    if (flyer) {
      drawFlyer(ctx, s, flyer);
    }

    // The tower, drawn from the floor up. The most recent slab is brightest and
    // the rest fade back, which is what keeps the top edge readable at a glance.
    // Slabs pushed off the bottom by the camera are skipped, so a hundred layers
    // costs the same as ten.
    for (let i = 0; i < tower.length; i++) {
      let y = slabY(i, s);
      if (y > s) {
        continue;
      }
      let fromTop = tower.length - 1 - i;
      let fresh = fromTop === 0;
      drawSlab(
        ctx,
        s,
        tower[i].x,
        y,
        tower[i].w,
        fresh ? A.theme.fg : A.theme.muted,
        fresh ? 1 : Math.max(0.18, 0.5 - fromTop * 0.03)
      );
    }

    // The scraps on their way down.
    for (let i = 0; i < scraps.length; i++) {
      let sc = scraps[i];
      drawSlab(ctx, s, sc.x, sc.y * s, sc.w, A.theme.muted, 0.4);
    }

    // The slab you are aiming, in the accent so it is never confused with the
    // tower, hanging just above whatever the current top is, plus a hairline
    // down to the landing zone.
    if (slab) {
      let top = towerTopY(s);
      let y = top - SLAB_H * 1.7 * s;
      drawSlab(ctx, s, slab.x, y, slab.w, A.theme.accent);

      ctx.save();
      ctx.globalAlpha = 0.25;
      ctx.strokeStyle = A.theme.accent;
      ctx.lineWidth = Math.max(1, s * 0.002);
      ctx.beginPath();
      ctx.moveTo(slab.x * s, y + SLAB_H * s);
      ctx.lineTo(slab.x * s, top);
      ctx.stroke();
      ctx.restore();
    }

    if (perfectFlash > 0) {
      // Small, and it follows the tower rather than sitting at a fixed height.
      // At 0.055 in the middle of the board it covered the very spot the eye
      // needs to read the next drop; pinned to the top of the board it was
      // nowhere near the action during the opening layers, when the tower is
      // still down on the floor.
      ctx.save();
      ctx.globalAlpha = Math.min(1, perfectFlash / PERFECT_STEPS) * 0.85;
      ctx.fillStyle = A.theme.accent;
      ctx.font = "700 " + Math.round(s * 0.032) + "px -apple-system, Helvetica, Arial, sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      let y = Math.max(0.05, towerTopFraction() - SLAB_H * 3.4);
      ctx.fillText("PERFECT", s * 0.5, y * s);
      ctx.restore();
    }
  }

  // Read-only, for the specs, same convention as the other games. sliceFor and
  // marginAt are the entire game in two functions, and neither is visible from
  // the outside: a tower with a broken slice still "reports a score".
  window.Stack = {
    state() {
      return {
        alive,
        layers,
        perfectRun,
        bestPerfectRun,
        slab: slab && { x: slab.x, w: slab.w, dir: slab.dir },
        top: topSlab() && { x: topSlab().x, w: topSlab().w },
        towerHeight: tower.length,
        scraps: scraps.length,
        sky: flyer && { type: flyer.type, x: flyer.x },
        config: {
          startWidth: START_W,
          minWidth: MIN_W,
          marginStart: MARGIN_START,
          marginDecay: MARGIN_DECAY,
        },
      };
    },
    rules: { sliceFor, marginAt, speedAt, skyStageFor },
  };

  tower.push({ x: 0.5, w: START_W });
  nextSlab();
  updateHint();

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
