/* 2048 for the Discourse arcade.
 *
 * Contract with the host page (see arcade-frame.js):
 *   on load      -> postMessage { type: "arcade:ready" }
 *   on game over -> postMessage { type: "arcade:score", score: <int> }
 *
 * There is deliberately no in-game restart. One run is one score, and a new
 * run has to be started by the host so the server can issue a fresh token.
 */
(function () {
  "use strict";

  let SIZE = 4;
  let SWIPE_THRESHOLD = 24;

  let boardEl = document.getElementById("board");
  let scoreEl = document.getElementById("score");
  let overEl = document.getElementById("over");

  let grid = [];
  let cells = [];
  let score = 0;
  let finished = false;

  // ── Theme ────────────────────────────────────────────────
  // The host passes its colour scheme in the query string. Values are
  // validated so the URL cannot inject arbitrary CSS.
  function applyTheme() {
    let params = new URLSearchParams(location.search);
    let safe =
      /^(#[0-9a-f]{3,8}|rgba?\([\d\s.,%/]+\)|hsla?\([\d\s.,%/]+\))$/i;

    ["bg", "fg", "accent", "muted", "low"].forEach(function (key) {
      let value = (params.get(key) || "").trim();
      if (value && safe.test(value)) {
        document.documentElement.style.setProperty("--" + key, value);
      }
    });
  }

  // ── Board helpers ────────────────────────────────────────

  function buildCells() {
    for (let i = 0; i < SIZE * SIZE; i++) {
      let el = document.createElement("div");
      el.className = "cell";
      el.dataset.v = "0";
      boardEl.appendChild(el);
      cells.push(el);
    }
    // Keep the game-over layer on top of the freshly added cells.
    boardEl.appendChild(overEl);
  }

  function emptyIndexes() {
    let out = [];
    for (let i = 0; i < grid.length; i++) {
      if (grid[i] === 0) {
        out.push(i);
      }
    }
    return out;
  }

  function addTile() {
    let free = emptyIndexes();
    if (!free.length) {
      return;
    }
    let index = free[Math.floor(Math.random() * free.length)];
    grid[index] = Math.random() < 0.9 ? 2 : 4;
  }

  // Index order per line, "first" meaning closest to the swipe direction.
  function linesFor(dir) {
    let lines = [];
    for (let i = 0; i < SIZE; i++) {
      let line = [];
      for (let j = 0; j < SIZE; j++) {
        if (dir === "left") {
          line.push(i * SIZE + j);
        } else if (dir === "right") {
          line.push(i * SIZE + (SIZE - 1 - j));
        } else if (dir === "up") {
          line.push(j * SIZE + i);
        } else {
          line.push((SIZE - 1 - j) * SIZE + i);
        }
      }
      lines.push(line);
    }
    return lines;
  }

  // Slide everything to the front, merging equal neighbours once each.
  function collapse(values) {
    let nums = values.filter(function (v) {
      return v !== 0;
    });
    let out = [];
    let gained = 0;

    for (let i = 0; i < nums.length; i++) {
      if (i + 1 < nums.length && nums[i] === nums[i + 1]) {
        let merged = nums[i] * 2;
        out.push(merged);
        gained += merged;
        i++;
      } else {
        out.push(nums[i]);
      }
    }

    while (out.length < SIZE) {
      out.push(0);
    }

    return { out, gained };
  }

  function hasMoves() {
    if (emptyIndexes().length) {
      return true;
    }

    for (let r = 0; r < SIZE; r++) {
      for (let c = 0; c < SIZE; c++) {
        let v = grid[r * SIZE + c];
        if (c + 1 < SIZE && grid[r * SIZE + c + 1] === v) {
          return true;
        }
        if (r + 1 < SIZE && grid[(r + 1) * SIZE + c] === v) {
          return true;
        }
      }
    }

    return false;
  }

  function move(dir) {
    if (finished) {
      return;
    }

    let moved = false;
    let gained = 0;

    linesFor(dir).forEach(function (line) {
      let before = line.map(function (index) {
        return grid[index];
      });
      let result = collapse(before);

      for (let k = 0; k < SIZE; k++) {
        if (grid[line[k]] !== result.out[k]) {
          moved = true;
        }
        grid[line[k]] = result.out[k];
      }

      gained += result.gained;
    });

    if (!moved) {
      return;
    }

    score += gained;
    addTile();
    render();

    if (!hasMoves()) {
      endGame();
    }
  }

  function render() {
    for (let i = 0; i < cells.length; i++) {
      let value = grid[i];
      let el = cells[i];

      el.dataset.v = String(value);
      el.textContent = value === 0 ? "" : String(value);
      el.classList.toggle("big", value > 2048);
      el.classList.toggle("small", value >= 1024);
    }

    scoreEl.textContent = String(score);
  }

  function post(message) {
    // The frame is sandboxed, so it has an opaque origin and cannot know the
    // host's origin. The payload is a plain score, nothing secret.
    parent.postMessage(message, "*");
  }

  function endGame() {
    finished = true;
    overEl.classList.add("visible");
    post({ type: "arcade:score", score });
  }

  // ── Input ────────────────────────────────────────────────

  let KEYS = {
    ArrowLeft: "left",
    ArrowRight: "right",
    ArrowUp: "up",
    ArrowDown: "down",
    a: "left",
    d: "right",
    w: "up",
    s: "down",
  };

  function bindInput() {
    window.addEventListener("keydown", function (event) {
      let dir = KEYS[event.key];
      if (!dir) {
        return;
      }
      event.preventDefault();
      move(dir);
    });

    let startX = 0;
    let startY = 0;
    let tracking = false;

    boardEl.addEventListener(
      "touchstart",
      function (event) {
        let touch = event.touches[0];
        startX = touch.clientX;
        startY = touch.clientY;
        tracking = true;
      },
      { passive: true }
    );

    boardEl.addEventListener(
      "touchmove",
      function (event) {
        // Stops the page rubber-banding while swiping the board.
        if (tracking) {
          event.preventDefault();
        }
      },
      { passive: false }
    );

    boardEl.addEventListener("touchend", function (event) {
      if (!tracking) {
        return;
      }
      tracking = false;

      let touch = event.changedTouches[0];
      let dx = touch.clientX - startX;
      let dy = touch.clientY - startY;
      let absX = Math.abs(dx);
      let absY = Math.abs(dy);

      if (Math.max(absX, absY) < SWIPE_THRESHOLD) {
        return;
      }

      if (absX > absY) {
        move(dx > 0 ? "right" : "left");
      } else {
        move(dy > 0 ? "down" : "up");
      }
    });
  }

  // ── Start ────────────────────────────────────────────────

  applyTheme();
  buildCells();

  grid = new Array(SIZE * SIZE).fill(0);
  addTile();
  addTile();
  render();

  bindInput();

  // Exposed so the rule specs can check the merge logic directly. It is a pure
  // function and scores are validated server side anyway, so this hands a
  // player nothing they could not already read in this file.
  window.Game2048 = { collapse, SIZE };

  post({ type: "arcade:ready" });
})();
