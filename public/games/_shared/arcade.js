/* Shared helpers for arcade games we write ourselves.
 *
 * Optional: a third-party game only has to speak the two-message contract
 * (see the plugin README). This just removes the boilerplate from our own.
 *
 *   Arcade.theme            colours handed over by the host
 *   Arcade.ready()          tell the host the game is playable
 *   Arcade.submit(score)    report the final score, once per document
 *   Arcade.canvas(el)       canvas sized for the device pixel ratio
 *   Arcade.onSwipe(el, fn)  fn("left" | "right" | "up" | "down")
 *   Arcade.onKeys(fn)       same directions, from arrows or WASD
 *   Arcade.onDrag(el, fn)   fn(ratio) where ratio is 0..1 across the element
 *   Arcade.onAim(el, opts)  opts.onMove / opts.onRelease with element coords
 *   Arcade.onTap(el, fn)    fn(point) with element coords
 */
(function () {
  "use strict";

  let COLOR = /^(#[0-9a-f]{3,8}|rgba?\([\d\s.,%/]+\)|hsla?\([\d\s.,%/]+\))$/i;
  let THEME_KEYS = ["bg", "fg", "accent", "muted", "low"];
  let FALLBACK = {
    bg: "#ffffff",
    fg: "#222222",
    accent: "#0088cc",
    muted: "#8f8f8f",
    low: "#e9e9e9",
  };

  // Values arrive in a URL, so anything that is not a plain colour is dropped
  // rather than written into a style.
  function readTheme() {
    let params = new URLSearchParams(location.search);
    let theme = {};

    THEME_KEYS.forEach(function (key) {
      let value = (params.get(key) || "").trim();
      let ok = value && COLOR.test(value);
      theme[key] = ok ? value : FALLBACK[key];
      if (ok) {
        document.documentElement.style.setProperty("--" + key, value);
      }
    });

    return theme;
  }

  let submitted = false;

  function post(message) {
    // The frame is sandboxed and has an opaque origin, so it cannot know the
    // host's origin. The payload is a plain score, nothing secret.
    parent.postMessage(message, "*");
  }

  function submit(score) {
    if (submitted) {
      return;
    }
    submitted = true;
    post({ type: "arcade:score", score: Math.max(0, Math.round(score) || 0) });
  }

  function ready() {
    post({ type: "arcade:ready" });
  }

  function canvas(el) {
    let ctx = el.getContext("2d");
    let width = 0;
    let height = 0;

    function resize() {
      let rect = el.getBoundingClientRect();
      let dpr = window.devicePixelRatio || 1;

      width = rect.width;
      height = rect.height;
      el.width = Math.round(width * dpr);
      el.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    resize();
    window.addEventListener("resize", resize);

    return {
      ctx,
      resize,
      get w() {
        return width;
      },
      get h() {
        return height;
      },
    };
  }

  function onSwipe(el, handler, threshold) {
    let limit = threshold || 20;
    let startX = 0;
    let startY = 0;
    let tracking = false;

    el.addEventListener(
      "touchstart",
      function (event) {
        let touch = event.touches[0];
        startX = touch.clientX;
        startY = touch.clientY;
        tracking = true;
      },
      { passive: true }
    );

    el.addEventListener(
      "touchmove",
      function (event) {
        // Stops the page rubber-banding while swiping the stage.
        if (tracking) {
          event.preventDefault();
        }
      },
      { passive: false }
    );

    el.addEventListener("touchend", function (event) {
      if (!tracking) {
        return;
      }
      tracking = false;

      let touch = event.changedTouches[0];
      let dx = touch.clientX - startX;
      let dy = touch.clientY - startY;

      if (Math.max(Math.abs(dx), Math.abs(dy)) < limit) {
        return;
      }

      if (Math.abs(dx) > Math.abs(dy)) {
        handler(dx > 0 ? "right" : "left");
      } else {
        handler(dy > 0 ? "down" : "up");
      }
    });
  }

  let KEYMAP = {
    ArrowLeft: "left",
    ArrowRight: "right",
    ArrowUp: "up",
    ArrowDown: "down",
    a: "left",
    d: "right",
    w: "up",
    s: "down",
    A: "left",
    D: "right",
    W: "up",
    S: "down",
  };

  function onKeys(handler) {
    window.addEventListener("keydown", function (event) {
      let dir = KEYMAP[event.key];
      if (!dir) {
        return;
      }
      event.preventDefault();
      handler(dir);
    });
  }

  // Which direction keys are down right now, for anything that turns or thrusts
  // while a key is held. onKeys only reports keydown, so holding a key leans on
  // the operating system's key repeat: one event, then roughly half a second of
  // nothing, then a burst. That reads as stiff and is not fixable by tuning.
  function keysHeld() {
    const held = new Set();

    window.addEventListener("keydown", function (event) {
      const dir = KEYMAP[event.key];
      if (!dir) {
        return;
      }
      event.preventDefault();
      held.add(dir);
    });

    window.addEventListener("keyup", function (event) {
      const dir = KEYMAP[event.key];
      if (dir) {
        held.delete(dir);
      }
    });

    // Losing focus mid-press would otherwise leave a key stuck down for good.
    window.addEventListener("blur", function () {
      held.clear();
    });

    return {
      has(dir) {
        return held.has(dir);
      },
    };
  }

  function ratioAcross(el, clientX) {
    let rect = el.getBoundingClientRect();
    if (rect.width <= 0) {
      return 0.5;
    }
    return Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
  }

  function onDrag(el, handler) {
    function report(event) {
      if (event.pointerType !== "mouse") {
        event.preventDefault();
      }
      handler(ratioAcross(el, event.clientX));
    }

    el.addEventListener("pointerdown", report);
    el.addEventListener("pointermove", report);
  }

  function localPoint(el, event) {
    let rect = el.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }

  function onTap(el, handler) {
    el.addEventListener("pointerdown", function (event) {
      event.preventDefault();
      handler(localPoint(el, event));
    });
  }

  function onAim(el, opts) {
    let from = null;

    el.addEventListener("pointerdown", function (event) {
      from = localPoint(el, event);

      // Capture keeps move events coming if the finger leaves the stage
      // mid-drag. It throws on pointer ids the browser is not tracking, and a
      // failed capture must not cost the player their shot.
      if (el.setPointerCapture) {
        try {
          el.setPointerCapture(event.pointerId);
        } catch {
          // Aiming still works without capture.
        }
      }

      if (opts.onStart) {
        opts.onStart(from);
      }
    });

    el.addEventListener("pointermove", function (event) {
      if (!from) {
        return;
      }
      event.preventDefault();
      if (opts.onMove) {
        opts.onMove(from, localPoint(el, event));
      }
    });

    function finish(event) {
      if (!from) {
        return;
      }
      let start = from;
      from = null;
      if (opts.onRelease) {
        opts.onRelease(start, localPoint(el, event));
      }
    }

    el.addEventListener("pointerup", finish);
    el.addEventListener("pointercancel", function () {
      from = null;
      if (opts.onCancel) {
        opts.onCancel();
      }
    });
  }

  // A fixed-step loop, so game speed does not depend on frame rate.
  function loop(stepMsGetter, step, draw) {
    let last = null;
    let acc = 0;

    function frame(now) {
      if (last === null) {
        last = now;
      }
      let delta = Math.min(250, now - last);
      last = now;
      acc += delta;

      let stepMs = stepMsGetter();
      let guard = 0;
      while (acc >= stepMs && guard < 10) {
        acc -= stepMs;
        guard++;
        step();
        stepMs = stepMsGetter();
      }

      draw();
      requestAnimationFrame(frame);
    }

    requestAnimationFrame(frame);
  }

  window.Arcade = {
    theme: readTheme(),
    ready,
    submit,
    canvas,
    onSwipe,
    onKeys,
    keysHeld,
    onDrag,
    onAim,
    onTap,
    loop,
  };
})();
