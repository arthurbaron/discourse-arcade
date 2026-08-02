# frozen_string_literal: true

# Debris felt stiff to turn with the keyboard. The cause was that the game
# nudged the heading once per keydown, so holding a key leaned on the operating
# system's key repeat: one turn, roughly half a second of nothing, then a burst.
# No amount of tuning the turn rate fixes that, because the input itself arrives
# in lumps.
#
# It now tracks which keys are down and turns on every step. That is a property a
# spec can check, and no amount of playing it in a hidden browser tab can, since
# requestAnimationFrame does not run there and nothing moves at all.

require "rails_helper"

RSpec.describe "Debris controls", type: :system do
  fab!(:player) { Fabricate(:user) }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before do
    sign_in(player)
    visit "/plugins/discourse-arcade/games/debris/index.html?#{theme}"
    expect(page).to have_css("#stage")
  end

  def hold(key)
    page.execute_script(
      "window.dispatchEvent(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));",
    )
  end

  def release(key)
    page.execute_script(
      "window.dispatchEvent(new KeyboardEvent('keyup', { key: '#{key}', bubbles: true }));",
    )
  end

  def sample_headings(count, gap: 0.05)
    Array.new(count) do
      value = page.evaluate_script("window.Debris.state().ship.heading")
      sleep gap
      value
    end
  end

  it "turns continuously while a key is held, not in bursts" do
    hold("ArrowLeft")
    headings = sample_headings(18)
    release("ArrowLeft")

    deltas = headings.each_cons(2).map { |a, b| (b - a).abs }
    turning = deltas.count { |d| d > 0.001 }

    # The old behaviour left a long dead stretch at the start while the operating
    # system waited to begin repeating, so most samples showed no movement.
    expect(turning).to be >= (deltas.length * 0.8).floor
    expect((headings.last - headings.first).abs).to be > 2.0
  end

  it "stops turning the moment the key is released" do
    hold("ArrowRight")
    sleep 0.3
    release("ArrowRight")

    sleep 0.1
    settled = page.evaluate_script("window.Debris.state().ship.heading")
    sleep 0.4

    expect(page.evaluate_script("window.Debris.state().ship.heading")).to be_within(
      0.01,
    ).of(settled)
  end

  it "thrusts while the up key is held and coasts after it" do
    expect(page.evaluate_script("window.Debris.state().thrusting")).to eq(false)

    hold("ArrowUp")
    sleep 0.2
    expect(page.evaluate_script("window.Debris.state().thrusting")).to eq(true)

    release("ArrowUp")
    sleep 0.1
    expect(page.evaluate_script("window.Debris.state().thrusting")).to eq(false)
  end

  # Touch is a different path from the keyboard: it eases towards wherever the
  # finger is rather than rotating directly, so it needs its own check. Bounded so
  # a mid-measurement death cannot pollute it, and sampled a little coarser than
  # the frame rate: the simulation runs in fixed 16ms steps, so a per-frame sample
  # can legitimately land between two of them and see no change.
  it "eases smoothly towards a held finger" do
    samples =
      page.evaluate_script(<<~JS)
        (function () {
          const stage = document.getElementById("stage");
          const r = stage.getBoundingClientRect();

          function send(type, nx, ny) {
            stage.dispatchEvent(new PointerEvent(type, {
              clientX: r.left + r.width * nx,
              clientY: r.top + r.height * ny,
              pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
            }));
          }

          // It starts pointing up, so a finger straight below is the furthest it
          // can be asked to turn.
          const startLives = window.Debris.state().lives;
          send("pointerdown", 0.5, 0.95);
          send("pointermove", 0.5, 0.95);

          return new Promise(function (resolve) {
            const out = [];
            const timer = setInterval(function () {
              const s = window.Debris.state();
              // Stop before a respawn resets the heading and ruins the run.
              if (s.lives !== startLives || out.length >= 16) {
                clearInterval(timer);
                resolve(out);
                return;
              }
              out.push(s.ship.heading);
            }, 40);
          });
        })();
      JS

    expect(samples.length).to be >= 10

    deltas = samples.each_cons(2).map { |a, b| b - a }

    # It swings the whole way round without ever turning back on itself, which is
    # what a stall or a fight between the two input paths would look like.
    expect(deltas.count(&:negative?)).to eq(0)
    expect(deltas.count { |d| d.abs < 0.0001 }).to be <= (deltas.length * 0.25).ceil
    expect((samples.last - samples.first).abs).to be > 1.5
  end
  # The touch rule that makes coasting possible: a tap only turns, a hold turns
  # and thrusts. Without the split, every turn on a phone also accelerated, so you
  # could never line up a shot while drifting.
  def touch(x, y, hold_seconds: 0)
    page.execute_script(<<~JS)
      (function () {
        const stage = document.getElementById("stage");
        const r = stage.getBoundingClientRect();
        window.__send = function (type) {
          stage.dispatchEvent(new PointerEvent(type, {
            clientX: r.left + r.width * #{x},
            clientY: r.top + r.height * #{y},
            pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
          }));
        };
        window.__send("pointerdown");
        window.__send("pointermove");
      })();
    JS

    sleep hold_seconds if hold_seconds.positive?
  end

  def lift
    page.execute_script('window.__send("pointerup");')
  end

  it "turns on a tap without thrusting" do
    before_heading = page.evaluate_script("window.Debris.state().ship.heading")

    touch(0.5, 0.95)
    # Well under the hold threshold, so this is a tap.
    sleep 0.06
    thrusting_during_tap = page.evaluate_script("window.Debris.state().thrusting")
    lift

    sleep 0.4
    after_heading = page.evaluate_script("window.Debris.state().ship.heading")

    expect(thrusting_during_tap).to eq(false)
    expect((after_heading - before_heading).abs).to be > 0.2
  end

  it "thrusts once the finger stays down" do
    touch(0.5, 0.95, hold_seconds: 0.45)

    expect(page.evaluate_script("window.Debris.state().thrusting")).to eq(true)

    lift
    sleep 0.1
    expect(page.evaluate_script("window.Debris.state().thrusting")).to eq(false)
  end
end
