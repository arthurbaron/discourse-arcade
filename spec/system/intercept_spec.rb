# frozen_string_literal: true

# The contract spec only proves Intercept ends and reports a score, which it
# would do just as happily if tapping did nothing at all. These check the two
# things the game is actually about: a led shot destroys a missile, and firing
# costs ammo you then run out of.

require "rails_helper"

RSpec.describe "Intercept", type: :system do
  fab!(:player) { Fabricate(:user) }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before do
    sign_in(player)
    visit "/plugins/discourse-arcade/games/intercept/index.html?#{theme}"
    expect(page).to have_css("#stage")
  end

  # Fires at where a missile is going rather than where it is, which is the whole
  # skill of the game and the only way a shot ever connects.
  def drive(stop_when:)
    page.execute_script(<<~JS)
      (function () {
        const stage = document.getElementById("stage");
        const r = stage.getBoundingClientRect();
        const BATTERY = { x: 0.5, y: 0.92 };
        const COUNTER_SPEED = 0.017;

        function tap(nx, ny) {
          stage.dispatchEvent(new PointerEvent("pointerdown", {
            clientX: r.left + r.width * nx,
            clientY: r.top + r.height * ny,
            pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
          }));
        }

        // Fixed point: guess the flight time, move the missile that far, repeat.
        function lead(m) {
          let steps = 20;
          for (let i = 0; i < 4; i++) {
            const px = m.x + m.vx * steps;
            const py = m.y + m.vy * steps;
            steps = Math.hypot(px - BATTERY.x, py - BATTERY.y) / COUNTER_SPEED;
          }
          return { x: m.x + m.vx * steps, y: m.y + m.vy * steps };
        }

        window.__drive = setInterval(function () {
          const s = window.Intercept.state();
          if (#{stop_when}) { clearInterval(window.__drive); return; }
          if (s.ammo <= 0 || s.incoming.length === 0) { return; }

          // Whichever is furthest down, so the most urgent one.
          const target = s.incoming.reduce(function (a, b) {
            return b.y > a.y ? b : a;
          });
          if (target.y < 0.12) { return; }

          const aim = lead(target);
          if (aim.y > 0.1 && aim.y < 0.85 && aim.x > 0.02 && aim.x < 0.98) {
            tap(aim.x, aim.y);
          }
        }, 90);
      })();
    JS
  end

  def wait_for(expression, seconds: 40)
    (seconds * 10).times do
      return true if page.evaluate_script(expression)
      sleep 0.1
    end
    false
  end

  it "destroys missiles when the shot is led properly" do
    drive(stop_when: "s.score > 0")

    expect(wait_for("window.Intercept.state().score > 0")).to eq(true)
  end

  it "spends ammo and runs dry" do
    before_ammo = page.evaluate_script("window.Intercept.state().ammo")
    expect(before_ammo).to be > 0

    drive(stop_when: "false")

    expect(wait_for("window.Intercept.state().ammo < #{before_ammo}")).to eq(true)
    expect(wait_for("window.Intercept.state().ammo === 0", seconds: 60)).to eq(true)
  end
end
