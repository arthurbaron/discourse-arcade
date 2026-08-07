# frozen_string_literal: true

# Darts is board geometry plus a timing mechanic, and both halves are exactly
# the kind of thing a "does it report a score" spec can never catch: a board
# with sector 12 where 9 belongs still reports a score, and an aim line that
# never really locks still throws darts.
#
# Aiming is timing rather than pointer position, and that is the game's
# fairness decision: if darts landed where you click, a desktop mouse would sit
# on the treble twenty all day and the leaderboard would rank input devices.
# So these specs also pin that a tap locks one axis while the other keeps
# sweeping, and that where you lock is where the dart lands, within the small
# advertised wobble.

require "rails_helper"

RSpec.describe "Darts", type: :system do
  fab!(:player) { Fabricate(:user) }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before do
    sign_in(player)
    visit "/plugins/discourse-arcade/games/darts/index.html?#{theme}"
    expect(page).to have_css("#stage")
  end

  def state
    page.evaluate_script("window.Darts.state()")
  end

  def hit_at(x, y)
    page.evaluate_script("window.Darts.rules.hitAt(#{x}, #{y})")
  end

  def tap
    page.execute_script(<<~JS)
      document.getElementById("stage").dispatchEvent(new PointerEvent("pointerdown", {
        clientX: 10, clientY: 10, pointerId: 1, pointerType: "touch",
        bubbles: true, cancelable: true
      }));
    JS
  end

  describe "the board" do
    # Radii from the Darts Regulation Authority sheet, as fractions of the
    # double ring's outer edge. y is negative upwards, so the twenty is at the
    # top where it belongs.
    it "scores the bull, the outer bull, and a miss" do
      expect(hit_at(0, 0)["points"]).to eq(50)
      expect(hit_at(0, -0.06)["points"]).to eq(25)
      expect(hit_at(0, -1.01)["points"]).to eq(0)
      expect(hit_at(0.8, 0.8)["points"]).to eq(0)
    end

    it "scores the twenty through single, treble, and double" do
      expect(hit_at(0, -0.3)).to include("points" => 20, "label" => "20")
      expect(hit_at(0, -0.605)).to include("points" => 60, "label" => "T20")
      expect(hit_at(0, -0.976)).to include("points" => 40, "label" => "D20")
    end

    it "puts the cruel neighbours where the real board puts them" do
      # 18 degrees clockwise of the twenty sits the one, 18 anticlockwise the
      # five. This is the risk that makes treble hunting a gamble.
      angle = 18 * Math::PI / 180
      r = 0.78
      expect(hit_at(Math.sin(angle) * r, -Math.cos(angle) * r)["points"]).to eq(1)
      expect(hit_at(-Math.sin(angle) * r, -Math.cos(angle) * r)["points"]).to eq(5)
    end

    it "matches the full real sector order all the way round" do
      sectors = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
      sectors.each_with_index do |expected, index|
        angle = index * 18 * Math::PI / 180
        hit = hit_at(Math.sin(angle) * 0.78, -Math.cos(angle) * 0.78)
        expect(hit["points"]).to eq(expected), "sector #{index} should be #{expected}, got #{hit["points"]}"
      end
    end

    it "changes sector exactly on the nine degree boundary" do
      just_inside = 8.6 * Math::PI / 180
      just_outside = 9.4 * Math::PI / 180
      expect(hit_at(Math.sin(just_inside) * 0.78, -Math.cos(just_inside) * 0.78)["points"]).to eq(20)
      expect(hit_at(Math.sin(just_outside) * 0.78, -Math.cos(just_outside) * 0.78)["points"]).to eq(1)
    end

    it "scores the treble nineteen, which is the other professional target" do
      index = 11 # 19 sits at index 11 of the sector order
      angle = index * 18 * Math::PI / 180
      r = 0.605
      expect(hit_at(Math.sin(angle) * r, -Math.cos(angle) * r)).to include("points" => 57, "label" => "T19")
    end
  end

  describe "the aim" do
    it "sweeps until a tap locks it, one axis at a time" do
      expect(state["phase"]).to eq("aimX")

      # Three samples rather than two: a triangle wave can bounce back to the
      # same value at exactly the wrong moment, and once in a blue moon a spec
      # would flake on it.
      samples = Array.new(3) do
        value = state["sweep"]
        sleep 0.1
        value
      end
      expect(samples.uniq.length).to be > 1

      tap
      after_lock = state
      expect(after_lock["phase"]).to eq("aimY")
      locked = after_lock["lockedX"]

      # The locked axis holds still while the other keeps sweeping.
      sleep 0.15
      later = state
      expect(later["lockedX"]).to eq(locked)
      expect(later["sweep"]).not_to eq(after_lock["sweep"])
    end

    it "lands the dart where the two locks crossed, within the wobble" do
      tap
      sleep 0.12
      tap

      result = state
      expect(result["phase"]).to eq("result")
      hit = result["lastHit"]
      expect(hit).to be_present

      distance = Math.sqrt(((hit["x"] - hit["aimX"])**2) + ((hit["y"] - hit["aimY"])**2))
      expect(distance).to be <= result["config"]["wobble"] + 0.0001

      # And the points credited are exactly what the board says that spot is
      # worth.
      expect(result["total"]).to eq(hit_at(hit["x"], hit["y"])["points"])
      expect(result["dartsThrown"]).to eq(1)
    end

    it "ignores taps during the result pause, so a double tap cannot burn a dart" do
      tap
      sleep 0.12
      tap
      expect(state["phase"]).to eq("result")

      tap
      after = state
      expect(after["dartsThrown"]).to eq(1)
      expect(after["phase"]).to eq("result")
    end
  end

  describe "the 180" do
    it "pays the bonus only for three treble twenties in one visit" do
      expect(page.evaluate_script("window.Darts.rules.bonusFor([60, 60, 60])")).to eq(50)
      expect(page.evaluate_script("window.Darts.rules.bonusFor([60, 60, 57])")).to eq(0)
      expect(page.evaluate_script("window.Darts.rules.bonusFor([60, 60])")).to eq(0)
      expect(page.evaluate_script("window.Darts.rules.bonusFor([20, 60, 60])")).to eq(0)
    end

    # The sweep advances in fixed increments, so its positions form a grid,
    # and one of those positions sits within 0.008 of the treble twenty's
    # centre on each axis. Tapping exactly there plus the maximum wobble is
    # still inside the treble, so a watcher that taps on the right step hits
    # T20 every time. That is also, incidentally, the documented cheat
    # ceiling: scripts can do what thumbs cannot.
    it "flashes and pays when a visit is three treble twenties" do
      page.execute_script(<<~JS)
        window.__watcher = setInterval(function () {
          var s = window.Darts.state();
          if (!s.alive || s.dartsThrown >= 3) { clearInterval(window.__watcher); return; }
          var target = s.phase === "aimX" ? 0 : -0.6059;
          if ((s.phase === "aimX" || s.phase === "aimY") && Math.abs(s.sweep - target) < 0.008) {
            document.getElementById("stage").dispatchEvent(new PointerEvent("pointerdown", {
              clientX: 10, clientY: 10, pointerId: 1, pointerType: "touch",
              bubbles: true, cancelable: true
            }));
          }
        }, 4);
      JS

      # Three perfect darts at roughly a second of sweep each, plus pauses.
      result = nil
      100.times do
        result = state
        break if result["dartsThrown"] >= 3
        sleep 0.2
      end

      expect(result["dartsThrown"]).to eq(3)
      expect(result["hits"].map { |h| h["label"] }).to eq(%w[T20 T20 T20])
      expect(result["bonuses180"]).to eq(1)
      expect(result["total"]).to eq(180 + 50)
      expect(result["celebrating"]).to eq(true)
    end
  end

  describe "a full turn" do
    it "adds every dart to the total and ends after fifteen" do
      # Tap through all fifteen darts, letting the sweep sit wherever it is.
      # Each dart is two taps plus a 640ms result pause, so the whole turn
      # needs a good fifteen seconds of headroom.
      160.times do
        current = state
        break unless current["alive"]
        tap if %w[aimX aimY].include?(current["phase"])
        sleep 0.12
      end

      final = state
      expect(final["dartsThrown"]).to eq(15)
      expect(final["alive"]).to eq(false)

      # The total is the fifteen hits plus fifty per 180, an invariant that
      # holds whatever the blind taps happened to land on.
      expected = final["hits"].sum { |h| h["points"] } + final["bonuses180"] * 50
      expect(final["total"]).to eq(expected)
      expect(page).to have_css("#over.visible")
    end
  end
end
