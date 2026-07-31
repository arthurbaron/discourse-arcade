/* Dribble for the Discourse arcade. One run, one score: no in-game restart.
 *
 * Slide a finger (or use the arrow keys) to steer between the defenders coming
 * at you. Every row has a guaranteed gap wide enough to pass, so a run is never
 * unwinnable: it just gets faster, the rows come closer together, and the gap
 * narrows. Score is the distance covered.
 */
(function () {
  "use strict";

  var A = window.Arcade;

  var STEP_MS = 16;

  var PLAYER_Y = 0.82;
  var PLAYER_R = 0.032;
  var DEF_R = 0.036;
  var FOLLOW = 0.35;
  var KEY_NUDGE = 0.07;

  var BASE_SPEED = 0.0075;
  var MAX_SPEED = 0.021;
  var SPEED_OVER = 400; // metres over which speed doubles
  var METRES_PER_UNIT = 20;

  var ROW_SPACING_START = 0.42;
  var ROW_SPACING_MIN = 0.3;
  var ROW_TIGHTEN_OVER = 1500;

  // Half the width of the gap left open in every row. Even at its narrowest
  // this is more than twice the player, so there is always a way through.
  var GAP_HALF_START = 0.115;
  var GAP_HALF_MIN = 0.075;
  var GAP_TIGHTEN_OVER = 1200;

  var LINE_SPACING = 0.25;

  // Semantic rather than themed: defenders have to read as danger in both a
  // light and a dark colour scheme.
  var DANGER = "#d1594a";

  var stage = document.getElementById("stage");
  var view = A.canvas(document.getElementById("view"));
  var scoreEl = document.getElementById("score");
  var overEl = document.getElementById("over");

  var player = { x: 0.5, target: 0.5 };
  var defenders = [];
  var scroll = 0;
  var nextRowAt = 0.5;
  var metres = 0;
  var alive = true;

  function size() {
    return Math.min(view.w, view.h);
  }

  function clamp(value, low, high) {
    return Math.min(high, Math.max(low, value));
  }

  function lane(value) {
    return clamp(value, PLAYER_R, 1 - PLAYER_R);
  }

  function speed() {
    return Math.min(MAX_SPEED, BASE_SPEED * (1 + metres / SPEED_OVER));
  }

  function rowSpacing() {
    var t = Math.min(1, metres / ROW_TIGHTEN_OVER);
    return ROW_SPACING_START + (ROW_SPACING_MIN - ROW_SPACING_START) * t;
  }

  function gapHalf() {
    var t = Math.min(1, metres / GAP_TIGHTEN_OVER);
    return GAP_HALF_START + (GAP_HALF_MIN - GAP_HALF_START) * t;
  }

  function placeDefender(into, from, to) {
    var width = to - from;
    if (width < DEF_R * 2) {
      return;
    }
    into.push(from + DEF_R + Math.random() * (width - DEF_R * 2));
  }

  // Pick where the gap is first, then fill what is left. That is what makes
  // every row passable by construction rather than by luck.
  function buildRow(half) {
    var margin = 0.02;
    var low = half + margin;
    var high = 1 - half - margin;
    var gapCentre = low + Math.random() * (high - low);
    var xs = [];

    placeDefender(xs, 0, gapCentre - half);
    placeDefender(xs, gapCentre + half, 1);

    return { gapCentre: gapCentre, xs: xs };
  }

  function spawnRow() {
    var row = buildRow(gapHalf());

    for (var i = 0; i < row.xs.length; i++) {
      defenders.push({ x: row.xs[i], y: -DEF_R });
    }
  }

  function finish() {
    alive = false;
    overEl.classList.add("visible");
    A.submit(Math.floor(metres));
  }

  function step() {
    if (!alive) {
      return;
    }

    var v = speed();
    scroll += v;
    metres += v * METRES_PER_UNIT;
    scoreEl.textContent = String(Math.floor(metres));

    player.x = lane(player.x + (player.target - player.x) * FOLLOW);

    if (scroll >= nextRowAt) {
      spawnRow();
      nextRowAt = scroll + rowSpacing();
    }

    var reach = PLAYER_R + DEF_R;

    for (var i = defenders.length - 1; i >= 0; i--) {
      var defender = defenders[i];
      defender.y += v;

      if (defender.y - DEF_R > 1) {
        defenders.splice(i, 1);
        continue;
      }

      var dx = defender.x - player.x;
      var dy = defender.y - PLAYER_Y;

      if (dx * dx + dy * dy < reach * reach) {
        finish();
        return;
      }
    }
  }

  function draw() {
    var ctx = view.ctx;
    var s = size();

    ctx.clearRect(0, 0, view.w, view.h);
    ctx.fillStyle = A.theme.low;
    ctx.fillRect(0, 0, view.w, view.h);

    // Scrolling pitch lines. Without them the speed is impossible to read.
    ctx.save();
    ctx.globalAlpha = 0.3;
    ctx.strokeStyle = A.theme.muted;
    ctx.lineWidth = Math.max(1, s * 0.003);
    for (var y = -(scroll % LINE_SPACING); y <= 1; y += LINE_SPACING) {
      ctx.beginPath();
      ctx.moveTo(0, y * s);
      ctx.lineTo(s, y * s);
      ctx.stroke();
    }
    ctx.restore();

    ctx.fillStyle = DANGER;
    for (var i = 0; i < defenders.length; i++) {
      ctx.beginPath();
      ctx.arc(defenders[i].x * s, defenders[i].y * s, DEF_R * s, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.fillStyle = A.theme.fg;
    ctx.beginPath();
    ctx.arc(player.x * s, PLAYER_Y * s, PLAYER_R * s, 0, Math.PI * 2);
    ctx.fill();

    // The ball sits at their feet and leans the way they are moving.
    var lean = clamp((player.target - player.x) * 1.6, -PLAYER_R, PLAYER_R);
    ctx.fillStyle = A.theme.accent;
    ctx.beginPath();
    ctx.arc(
      (player.x + lean) * s,
      (PLAYER_Y - PLAYER_R - 0.016) * s,
      0.014 * s,
      0,
      Math.PI * 2
    );
    ctx.fill();
  }

  // Exposed for the specs, which check that every generated row really does
  // leave a gap the player fits through. Read-only row generation, and scores
  // are validated server side regardless.
  window.Dribble = {
    buildRow: buildRow,
    gapHalfAt: function (atMetres) {
      var t = Math.min(1, atMetres / GAP_TIGHTEN_OVER);
      return GAP_HALF_START + (GAP_HALF_MIN - GAP_HALF_START) * t;
    },
    sizes: { player: PLAYER_R, defender: DEF_R },
  };

  A.onDrag(stage, function (ratio) {
    player.target = lane(ratio);
  });

  A.onKeys(function (dir) {
    if (dir === "left") {
      player.target = lane(player.target - KEY_NUDGE);
    } else if (dir === "right") {
      player.target = lane(player.target + KEY_NUDGE);
    }
  });

  A.loop(function () {
    return STEP_MS;
  }, step, draw);

  A.ready();
})();
