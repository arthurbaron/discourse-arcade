# frozen_string_literal: true

# The two football games make a promise each that "it ends and reports a score"
# does not cover: Keepie Uppie has to be playable by someone who hits the ball,
# and every Dribble row has to leave a gap the player actually fits through.

require "rails_helper"

RSpec.describe "Football games", type: :system do
  fab!(:player) { Fabricate(:user) }

  THEME = "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"

  before { sign_in(player) }

  def open_game(slug)
    visit "/plugins/discourse-arcade/games/#{slug}/index.html?#{THEME}"
    expect(page).to have_css("#stage")
  end

  describe "Keepie Uppie" do
    before do
      open_game("keepie")
      expect(page.evaluate_script("typeof window.Keepie")).to eq("object")
    end

    it "keeps the ball up for a player who actually hits it" do
      # Taps land on the ball wherever it is, which is what a good player
      # manages. If the kick, the hitbox or the difficulty ramp break, this
      # collapses to a handful of touches.
      page.execute_script(<<~JS)
        (function () {
          var stage = document.getElementById("stage");
          var rect = stage.getBoundingClientRect();

          var id = setInterval(function () {
            var state = window.Keepie.state();
            if (!state.alive) {
              clearInterval(id);
              return;
            }
            stage.dispatchEvent(new PointerEvent("pointerdown", {
              clientX: rect.left + rect.width * state.x,
              clientY: rect.top + rect.height * state.y,
              pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
            }));
          }, 50);
        })();
      JS

      deadline = Time.now + 20
      loop do
        touches = page.evaluate_script("window.Keepie.state().touches")
        break if touches >= 15
        raise "only reached #{touches} touches" if Time.now > deadline
        sleep 0.2
      end

      expect(page.evaluate_script("window.Keepie.state().touches")).to be >= 15
    end

    it "ends the moment the ball reaches the floor" do
      # No taps at all: the opening kick-up has to come down and finish the run.
      expect(page).to have_css("#over.visible", wait: 10)

      state = page.evaluate_script("window.Keepie.state()")
      expect(state["alive"]).to eq(false)
      expect(state["y"] + state["r"]).to be_within(0.001).of(state["ground"])
    end
  end

  describe "Dribble" do
    before do
      open_game("dribble")
      expect(page.evaluate_script("typeof window.Dribble")).to eq("object")
    end

    it "always leaves a gap the player fits through, at every difficulty" do
      report =
        page.evaluate_script(<<~JS)
          (function () {
            var sizes = window.Dribble.sizes;
            var reach = sizes.player + sizes.defender;
            var problems = [];
            var rows = 0;
            var tightest = 1;

            // Sweep the whole difficulty curve, not just the opening metres.
            [0, 300, 600, 900, 1200, 5000].forEach(function (metres) {
              var half = window.Dribble.gapHalfAt(metres);

              for (var i = 0; i < 400; i++) {
                var row = window.Dribble.buildRow(half);
                rows++;

                // The player has to be able to sit in the gap without touching
                // anyone, and the gap has to be reachable on the pitch.
                if (row.gapCentre < sizes.player || row.gapCentre > 1 - sizes.player) {
                  problems.push("gap at " + row.gapCentre.toFixed(3) + " is off the pitch");
                }

                for (var d = 0; d < row.xs.length; d++) {
                  var clearance = Math.abs(row.xs[d] - row.gapCentre);
                  if (clearance < tightest) { tightest = clearance; }
                  if (clearance < reach) {
                    problems.push(
                      "defender " + row.xs[d].toFixed(3) +
                      " only " + clearance.toFixed(3) +
                      " from the gap, needs " + reach.toFixed(3)
                    );
                  }
                  if (row.xs[d] < sizes.defender || row.xs[d] > 1 - sizes.defender) {
                    problems.push("defender " + row.xs[d].toFixed(3) + " hangs off the pitch");
                  }
                }
              }
            });

            return {
              rows: rows,
              reach: reach,
              tightestClearance: tightest,
              problems: problems.slice(0, 5)
            };
          })()
        JS

      expect(report["problems"]).to eq([])
      expect(report["rows"]).to eq(2400)
      expect(report["tightestClearance"]).to be > report["reach"]
    end
  end
end
