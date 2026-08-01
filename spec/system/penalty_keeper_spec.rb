# frozen_string_literal: true

# The keeper used to stand on the line and only move sideways, which left the
# entire top half of the goal unreachable: a shot into either top corner was a
# guaranteed goal rather than a good one. These specs pin the two halves of the
# fix, because "the game still reports a score" cannot tell you the keeper is
# a statue.

require "rails_helper"

RSpec.describe "Penalty keeper", type: :system do
  fab!(:player) { Fabricate(:user) }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before do
    sign_in(player)
    visit "/plugins/discourse-arcade/games/penalty/index.html?#{theme}"
    expect(page).to have_css("#stage")
  end

  # Shoots once, as soon as the keeper is inside the given band, and reports
  # what happened along with how high he got.
  def shoot_when_keeper_between(keeper_min, keeper_max, target_x, target_y)
    page.execute_script(<<~JS)
      (function () {
        const stage = document.getElementById("stage");
        const r = stage.getBoundingClientRect();

        function send(type, x, y) {
          stage.dispatchEvent(new PointerEvent(type, {
            clientX: r.left + r.width * x,
            clientY: r.top + r.height * y,
            pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
          }));
        }

        window.__restY = window.Penalty.state().keeper.y;
        window.__highest = window.__restY;
        window.__outcome = null;
        window.__fired = false;
        let lastPhase = null;

        function tick() {
          const s = window.Penalty.state();
          window.__highest = Math.min(window.__highest, s.keeper.y);

          if (lastPhase === "flying" && s.phase === "result") {
            window.__outcome = s.outcome;
            return;
          }
          lastPhase = s.phase;

          if (!window.__fired && s.phase === "aiming" &&
              s.keeper.x >= #{keeper_min} && s.keeper.x <= #{keeper_max}) {
            send("pointerdown", 0.5, 0.87);
            send("pointermove", #{target_x}, #{target_y});
            send("pointerup", #{target_x}, #{target_y});
            window.__fired = true;
          }

          setTimeout(tick, 25);
        }

        tick();
      })();
    JS

    60.times do
      break if page.evaluate_script("window.__outcome !== null")
      sleep 0.2
    end

    {
      outcome: page.evaluate_script("window.__outcome"),
      rest_y: page.evaluate_script("window.__restY"),
      highest_y: page.evaluate_script("window.__highest"),
    }
  end

  it "dives upwards for a shot into the top corner" do
    result = shoot_when_keeper_between(0.0, 1.0, 0.16, 0.18)

    expect(result[:outcome]).to be_present
    # Lower y is higher up the goal. A keeper who cannot leave the ground is
    # the bug this exists to catch.
    expect(result[:highest_y]).to be < result[:rest_y] - 0.02
  end

  it "saves a shot straight at him" do
    # Waiting until he is near the middle and then shooting at the middle is the
    # shortest dive there is, so this must not be a goal.
    result = shoot_when_keeper_between(0.45, 0.55, 0.5, 0.34)

    expect(result[:outcome]).to eq("SAVED")
  end
end
