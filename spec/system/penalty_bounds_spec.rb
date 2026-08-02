# frozen_string_literal: true

# Penalty has now had two holes of the same shape. First the keeper could not
# leave the ground, so both top corners were certain goals. Then the verdict
# checked the crossbar and the posts but not the goal line, so the strip of ground
# between the line and the ball was a certain goal too.
#
# Patching a third hole and hoping is not a plan, so this walks the boundary
# instead. Two claims, and together they close the game:
#
#   Anything outside the goal mouth is a miss.
#   Anything inside it can be saved, so no spot is a free goal.
#
# Aim points keep a margin from the edges, because shots carry spread on purpose
# and a point right on a line could legitimately land either side of it.

require "rails_helper"

RSpec.describe "Penalty bounds", type: :system do
  fab!(:player) { Fabricate(:user) }

  GOAL = { left: 0.12, right: 0.88, top: 0.15, bottom: 0.53 }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before { sign_in(player) }

  # One fresh run, one shot, one outcome. Fresh each time because a save and a
  # miss both cost a life and there are only three.
  def outcome_for(x, y, align_keeper: false)
    visit "/plugins/discourse-arcade/games/penalty/index.html?#{theme}"
    expect(page).to have_css("#stage")

    page.execute_script(<<~JS)
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

        window.__outcome = null;
        let lastPhase = null;

        function tick() {
          const s = window.Penalty.state();

          if (lastPhase === "flying" && s.phase === "result") {
            window.__outcome = s.outcome;
            return;
          }
          lastPhase = s.phase;

          if (s.phase === "aiming" && !window.__fired) {
            // Waiting for him to line up under the target is what makes "this
            // spot is reachable" a fair question rather than a lucky one.
            const lined = #{align_keeper} ? Math.abs(s.keeper.x - #{x}) < 0.05 : true;
            if (lined) {
              window.__fired = true;
              send("pointerdown", 0.5, 0.87);
              send("pointermove", #{x}, #{y});
              send("pointerup", #{x}, #{y});
            }
          }

          setTimeout(tick, 25);
        }

        tick();
      })();
    JS

    80.times do
      break if page.evaluate_script("window.__outcome !== null")
      sleep 0.15
    end

    page.evaluate_script("window.__outcome")
  end

  describe "outside the mouth" do
    it "calls a shot above the crossbar over" do
      expect(outcome_for(0.5, 0.05)).to eq("OVER")
    end

    it "calls a shot into the ground short of the line short" do
      # The exploit: this used to be a guaranteed goal, since the keeper's box
      # bottoms out on the line and can never come below it.
      expect(outcome_for(0.5, 0.65)).to eq("SHORT")
    end

    it "calls a low shot off to the side short as well" do
      expect(outcome_for(0.25, 0.72)).to eq("SHORT")
    end

    it "calls a shot outside the left post wide" do
      expect(outcome_for(0.04, 0.30)).to eq("WIDE")
    end

    it "calls a shot outside the right post wide" do
      expect(outcome_for(0.96, 0.30)).to eq("WIDE")
    end
  end

  describe "inside the mouth" do
    # If any of these ever comes back GOAL with the keeper standing right there,
    # that spot is unreachable and the game has another free corner.
    [
      ["straight down the middle", 0.5, 0.34],
      ["just inside the goal line", 0.5, 0.47],
      ["high on the left", 0.20, 0.22],
      ["high on the right", 0.80, 0.22],
      ["low on the left", 0.20, 0.46],
      ["low on the right", 0.80, 0.46],
    ].each do |label, x, y|
      it "can be saved: #{label}" do
        expect(outcome_for(x, y, align_keeper: true)).to eq("SAVED")
      end
    end
  end
end
