# frozen_string_literal: true

# Dying in Debris used to cost you the next life too.
#
# One counter did two jobs: waiting to come back, and the grace period once
# back. It counted 70 steps down to 1 and then held at 1 until the middle of the
# field was clear, and the blink formula reads `floor(n / 6) % 2 === 0`, which at
# n = 1 means hidden. So the whole wait was spent fully invisible rather than
# blinking. Meanwhile the ship's physics kept running, so a finger still on the
# glass flew a ship nobody could see, and the clear-the-middle check watched the
# middle while the ship was somewhere else entirely. The moment the counter
# reached zero you became solid wherever you had drifted to, usually into a rock.
#
# Measured on the old code: 2.48 field-widths of travel in three seconds, under
# thrust for every one of 120 samples, and a second life gone inside that window.
#
# Waiting for the middle to clear turned out to be the wrong idea on its own
# terms as well. The ship does not shoot while it is away, so nothing clears the
# middle, and one traced run sat there for the full two seconds of the window
# without returning. Hence a fixed wait to a chosen spot, protected on arrival.

require "rails_helper"

RSpec.describe "Debris respawn", type: :system do
  fab!(:player) { Fabricate(:user) }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before do
    sign_in(player)
    visit "/plugins/discourse-arcade/games/debris/index.html?#{theme}"
    expect(page).to have_css("#stage")
  end

  # Flies into a rock with the finger held down, which is the situation a real
  # player is in when they die, and keeps holding it afterwards while reporting
  # what the ship does. A stationary ship shoots away whatever would hit it, so
  # dying has to be done on purpose.
  def die_then_watch(ms: 1500)
    result = page.evaluate_script(<<~JS)
      (function () {
        const stage = document.getElementById("stage");
        const r = stage.getBoundingClientRect();

        // The stage is square and the canvas fills it, so game coordinates are
        // fractions of the stage rect.
        function send(type, nx, ny) {
          stage.dispatchEvent(new PointerEvent(type, {
            clientX: r.left + r.width * nx,
            clientY: r.top + r.height * ny,
            pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
          }));
        }

        function wrapped(a, b) {
          let d = a - b;
          if (d > 0.5) { d -= 1; } else if (d < -0.5) { d += 1; }
          return d;
        }

        function nearestRock(s) {
          let best = null;
          let bestDistance = 9;
          for (const rock of s.rocks) {
            const d = Math.hypot(
              wrapped(rock.x, s.ship.x),
              wrapped(rock.y, s.ship.y)
            );
            if (d < bestDistance) { bestDistance = d; best = rock; }
          }
          return best;
        }

        function clearance(s, x, y) {
          let nearest = 9;
          for (const rock of s.rocks) {
            const d =
              Math.hypot(wrapped(rock.x, x), wrapped(rock.y, y)) - rock.r;
            if (d < nearest) { nearest = d; }
          }
          return nearest;
        }

        const startLives = window.Debris.state().lives;
        let down = false;

        return new Promise(function (resolve) {
          const chase = setInterval(function () {
            const s = window.Debris.state();

            if (s.lives < startLives) {
              clearInterval(chase);
              watch(s.lives);
              return;
            }

            const rock = nearestRock(s);
            if (!rock) { return; }
            if (!down) { send("pointerdown", rock.x, rock.y); down = true; }
            send("pointermove", rock.x, rock.y);
          }, 30);

          // The finger stays down through the death on purpose.
          function watch(livesAtDeath) {
            const samples = [];
            const started = performance.now();

            const watcher = setInterval(function () {
              const s = window.Debris.state();
              samples.push({
                t: Math.round(performance.now() - started),
                x: s.ship.x,
                y: s.ship.y,
                lives: s.lives,
                on_field: s.onField,
                shielded: s.shielded,
                marker: s.returnSpot,
                // Measured live: a spec cannot recompute this later, because the
                // rocks have moved on by then.
                clearance: clearance(s, s.ship.x, s.ship.y),
              });

              if (performance.now() - started > #{ms}) {
                clearInterval(watcher);
                send("pointerup", 0.5, 0.5);
                resolve({ lives_at_death: livesAtDeath, samples: samples });
              }
            }, 25);
          }
        });
      })();
    JS

    # Nothing below means anything if the run that was captured was the player's
    # last life, because then there is no respawn to measure.
    expect(result["lives_at_death"]).to be > 0
    result
  end

  def travel(samples)
    samples
      .each_cons(2)
      .sum do |a, b|
        dx = (b["x"] - a["x"]).abs
        dy = (b["y"] - a["y"]).abs
        # Wrapping round an edge is not travel.
        dx = 0 if dx > 0.4
        dy = 0 if dy > 0.4
        Math.sqrt((dx**2) + (dy**2))
      end
  end

  it "holds the ship still while it is off the field, even with a finger down" do
    samples = die_then_watch["samples"]
    away = samples.take_while { |s| s["on_field"] == false }

    # Long enough to be a real wait, so the next assertion means something.
    expect(away.length).to be >= 8

    # The whole point: a ship nobody can see must not be flying.
    expect(travel(away)).to be < 0.01
  end

  it "always comes back, and quickly" do
    samples = die_then_watch["samples"]

    returned = samples.index { |s| s["on_field"] }
    expect(returned).to be_present

    # The old wait could sit indefinitely while the middle stayed busy, since
    # the ship does not shoot while it is away.
    expect(samples[returned]["t"]).to be < 1000
  end

  it "comes back where the marker promised, with room around it" do
    samples = die_then_watch["samples"]

    marker = samples.first["marker"]
    landed = samples[samples.index { |s| s["on_field"] }]

    # The faint outline shown during the wait is where the ship actually lands,
    # so the player has the whole wait to see where they are about to be.
    expect(landed["x"]).to be_within(0.02).of(marker["x"])
    expect(landed["y"]).to be_within(0.02).of(marker["y"])

    # And it is not dropped on top of a rock.
    expect(landed["clearance"]).to be > 0.05
  end

  # Everything above reads the game's own state. This one reads the canvas, so a
  # marker that was calculated but never painted would still be caught.
  it "paints the marker on the spot while the ship is away" do
    found = page.evaluate_script(<<~JS)
      (function () {
        const stage = document.getElementById("stage");
        const canvas = document.getElementById("view");
        const ctx = canvas.getContext("2d");
        const r = stage.getBoundingClientRect();

        function send(type, nx, ny) {
          stage.dispatchEvent(new PointerEvent(type, {
            clientX: r.left + r.width * nx, clientY: r.top + r.height * ny,
            pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
          }));
        }

        function wrapped(a, b) {
          let d = a - b;
          if (d > 0.5) { d -= 1; } else if (d < -0.5) { d += 1; }
          return d;
        }

        function nearestRock(s) {
          let best = null;
          let bestDistance = 9;
          for (const rock of s.rocks) {
            const d = Math.hypot(
              wrapped(rock.x, s.ship.x),
              wrapped(rock.y, s.ship.y)
            );
            if (d < bestDistance) { bestDistance = d; best = rock; }
          }
          return best;
        }

        // The accent is used for the ship and nothing else, and this spec's theme
        // makes it the only blue on the field.
        function accentPixels(nx, ny) {
          const half = Math.round(0.05 * canvas.width);
          const x = Math.max(0, Math.round(nx * canvas.width) - half);
          const y = Math.max(0, Math.round(ny * canvas.height) - half);
          const w = Math.min(canvas.width - x, half * 2);
          const h = Math.min(canvas.height - y, half * 2);
          const data = ctx.getImageData(x, y, w, h).data;
          let hits = 0;
          for (let i = 0; i < data.length; i += 4) {
            if (data[i + 2] > data[i] + 20) { hits++; }
          }
          return hits;
        }

        const startLives = window.Debris.state().lives;
        let down = false;

        return new Promise(function (resolve) {
          const chase = setInterval(function () {
            const s = window.Debris.state();
            if (s.lives < startLives) {
              clearInterval(chase);
              // Well inside the wait, and after a frame has been drawn.
              setTimeout(look, 250);
              return;
            }
            const rock = nearestRock(s);
            if (!rock) { return; }
            if (!down) { send("pointerdown", rock.x, rock.y); down = true; }
            send("pointermove", rock.x, rock.y);
          }, 30);

          function look() {
            const s = window.Debris.state();
            const result = {
              away: s.onField === false,
              at_marker: accentPixels(s.returnSpot.x, s.returnSpot.y),
              at_dead_ship: accentPixels(s.ship.x, s.ship.y),
            };
            send("pointerup", 0.5, 0.5);
            resolve(result);
          }
        });
      })();
    JS

    expect(found["away"]).to eq(true)

    # Something is drawn where the ship will land.
    expect(found["at_marker"]).to be > 20

    # And nothing is left behind where it died, which is what made the old
    # version so confusing to watch.
    expect(found["at_dead_ship"]).to eq(0)
  end

  it "comes back protected, so one crash cannot cost two lives" do
    result = die_then_watch
    samples = result["samples"]

    landed_at = samples.index { |s| s["on_field"] }
    expect(samples[landed_at]["shielded"]).to eq(true)

    # The complaint that started this. Dying again later in the run is fair
    # play, so this only covers the stretch the game promises to protect.
    protected_samples = samples.select { |s| s["on_field"] == false || s["shielded"] }
    expect(protected_samples.map { |s| s["lives"] }.uniq).to eq([result["lives_at_death"]])
  end
end
