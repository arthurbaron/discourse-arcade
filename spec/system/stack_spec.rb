# frozen_string_literal: true

# Stack is two functions wearing a game: the slice, which decides what survives
# a drop, and the forgiveness margin, which decides whether a near miss costs
# anything. Both are invisible from outside. A tower that slices the wrong side
# away, or one that forgives forever, still loads and still reports a score, so
# only the rules themselves can be held to account.
#
# The margin is the design. Fixed, it removes the ceiling entirely: simulated at
# expert timing it ran into a 5,000 layer guard, the same no-wall problem Penalty
# had in reverse. Decaying to zero at layer 13 gives an expert a mean of 47 and a
# best of 60 over 40,000 runs, a casual player 16, and a guaranteed end.
#
# It also has to survive a script with no timing error at all, which no margin
# rule can stop on its own. The discrete sweep does it: once the margin is gone
# the nearest reachable position is still half a step off centre, so even perfect
# play sheds a sliver. Simulated, that script dies at layer 92, which is what the
# plausibility ceiling is set against.

require "rails_helper"

RSpec.describe "Stack", type: :system do
  fab!(:player) { Fabricate(:user) }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before do
    sign_in(player)
    visit "/plugins/discourse-arcade/games/stack/index.html?#{theme}"
    expect(page).to have_css("#stage")
  end

  def state
    page.evaluate_script("window.Stack.state()")
  end

  def slice(landed, below, width, layer)
    page.evaluate_script("window.Stack.rules.sliceFor(#{landed}, #{below}, #{width}, #{layer})")
  end

  def margin(layer, width)
    page.evaluate_script("window.Stack.rules.marginAt(#{layer}, #{width})")
  end

  describe "the slice" do
    # Layer 30 is past where the margin reaches zero, so these are pure geometry
    # with no forgiveness in the way.
    it "keeps the whole slab on a dead centre drop" do
      result = slice(0.5, 0.5, 0.4, 30)
      expect(result["width"]).to be_within(0.0001).of(0.4)
      expect(result["centre"]).to be_within(0.0001).of(0.5)
      expect(result["lost"]).to be_within(0.0001).of(0)
    end

    it "keeps only the overlap, and centres what is left on it" do
      # Landed 0.1 right of a 0.4 wide slab: 0.3 survives, centred between them.
      result = slice(0.6, 0.5, 0.4, 30)
      expect(result["width"]).to be_within(0.0001).of(0.3)
      expect(result["centre"]).to be_within(0.0001).of(0.55)
      expect(result["lost"]).to be_within(0.0001).of(0.1)
    end

    it "slices the same amount whichever side it hangs over" do
      right = slice(0.62, 0.5, 0.4, 30)
      left = slice(0.38, 0.5, 0.4, 30)

      expect(left["width"]).to be_within(0.0001).of(right["width"])
      expect(left["lost"]).to be_within(0.0001).of(right["lost"])
      # And the survivor leans towards the side it landed on, in both directions.
      expect(right["centre"]).to be > 0.5
      expect(left["centre"]).to be < 0.5
    end

    it "throws the scrap out on the side that overhung" do
      right = slice(0.6, 0.5, 0.4, 30)
      left = slice(0.4, 0.5, 0.4, 30)

      expect(right["scrapCentre"]).to be > right["centre"]
      expect(left["scrapCentre"]).to be < left["centre"]
    end

    it "leaves nothing when the miss is the whole width" do
      result = slice(0.9, 0.5, 0.4, 30)
      expect(result["width"]).to eq(0)
    end
  end

  describe "the forgiveness margin" do
    it "snaps a near miss square onto the slab below, losing nothing" do
      # Layer 0, width 0.4: the margin is 9% of the width, so 0.03 is inside it.
      result = slice(0.53, 0.5, 0.4, 0)
      expect(result["snapped"]).to eq(true)
      expect(result["width"]).to be_within(0.0001).of(0.4)
      expect(result["centre"]).to be_within(0.0001).of(0.5)
      expect(result["lost"]).to eq(0)
    end

    it "shrinks with height and reaches zero, which is what ends every run" do
      # Strictly decreasing only while there is still margin left to lose. Past
      # the point it reaches zero it stays there, so "always decreasing" is the
      # wrong shape to assert and cost this spec one red run to notice.
      before_zero = (0..12).step(4).map { |layer| margin(layer, 0.4) }
      expect(before_zero.each_cons(2).all? { |a, b| b < a }).to eq(true)

      # 9% of the slab at the bottom, gone by layer 13. Reported from play: at
      # 14% a skilled player stacked nineteen layers without losing a sliver,
      # which is more than fit on screen, so the tower never looked like one.
      expect(margin(0, 0.4)).to be_within(0.0001).of(0.4 * 0.09)
      expect(margin(13, 0.4)).to eq(0)
      expect(margin(40, 0.4)).to eq(0)
      expect(margin(500, 0.4)).to eq(0)
    end

    it "scales with the slab, so a narrow slab gets a narrow margin" do
      expect(margin(0, 0.2)).to be_within(0.0001).of(margin(0, 0.4) / 2)
    end

    # The property the whole design turns on. A fixed margin would forgive the
    # same near miss at layer 40 as at layer 0, and a good player would never
    # lose a single sliver.
    it "stops forgiving the very miss it used to forgive" do
      forgiving = slice(0.52, 0.5, 0.4, 0)
      unforgiving = slice(0.52, 0.5, 0.4, 30)

      expect(forgiving["snapped"]).to eq(true)
      expect(unforgiving["snapped"]).to eq(false)
      expect(unforgiving["width"]).to be < 0.4
    end
  end

  describe "the sweep" do
    it "speeds up as the tower grows, up to a ceiling" do
      speeds = [0, 10, 20, 40, 80].map { |l| page.evaluate_script("window.Stack.rules.speedAt(#{l})") }

      expect(speeds.each_cons(2).all? { |a, b| b >= a }).to eq(true)
      expect(speeds.first).to be < speeds[3]
      # Capped, or it would eventually outrun a frame and teleport.
      expect(speeds.last).to be_within(0.0001).of(0.03)
    end

    it "slides back and forth inside the board rather than wrapping" do
      seen = Array.new(40) do
        value = state["slab"]["x"]
        sleep 0.05
        value
      end

      half = state["slab"]["w"] / 2
      expect(seen.min).to be >= half - 0.001
      expect(seen.max).to be <= 1 - half + 0.001

      # It has to turn around somewhere in there, not run one way forever.
      deltas = seen.each_cons(2).map { |a, b| b - a }
      expect(deltas.any?(&:positive?)).to eq(true)
      expect(deltas.any?(&:negative?)).to eq(true)
    end
  end

  describe "a played run" do
    # Taps whenever the sliding slab is within half a step of the one below,
    # which is the skilled player the balance simulation modelled.
    def play_well(max_layers)
      page.execute_script(<<~JS)
        window.__log = [];
        window.__done = false;
        window.__timer = setInterval(function () {
          var s = window.Stack.state();
          if (!s.alive || s.layers >= #{max_layers}) {
            clearInterval(window.__timer);
            window.__done = true;
            return;
          }
          if (!s.slab || !s.top) { return; }
          var speed = window.Stack.rules.speedAt(s.layers);
          if (Math.abs(s.slab.x - s.top.x) <= speed / 2) {
            document.getElementById("stage").dispatchEvent(new PointerEvent("pointerdown", {
              clientX: 10, clientY: 10, pointerId: 1, pointerType: "touch",
              bubbles: true, cancelable: true
            }));
          }
        }, 8);
      JS

      200.times do
        break if page.evaluate_script("window.__done")
        sleep 0.1
      end
    end

    it "stacks layers, never widens, and keeps the score in step" do
      play_well(12)

      result = state
      expect(result["layers"]).to be >= 8
      expect(result["towerHeight"]).to eq(result["layers"] + 1)
      expect(find("#score").text.to_i).to eq(result["layers"])

      # A slab can never be wider than the one it landed on. If it could, the
      # game would have no end at all.
      expect(result["slab"]["w"]).to be <= result["top"]["w"] + 0.0001
    end

    it "ends on its own once the slab runs out, and reports that score" do
      page.execute_script(<<~JS)
        window.__arcadeMsgs = [];
        window.addEventListener("message", function (e) {
          if (e.data && typeof e.data === "object" && e.data.type) {
            window.__arcadeMsgs.push(e.data);
          }
        });
      JS

      # Deliberately terrible: tap the instant the slab reaches an edge, so it
      # hangs over as far as it can every time and the tower dies quickly.
      page.execute_script(<<~JS)
        window.__timer = setInterval(function () {
          var s = window.Stack.state();
          if (!s.alive) { clearInterval(window.__timer); return; }
          if (!s.slab) { return; }
          var half = s.slab.w / 2;
          if (s.slab.x <= half + 0.002 || s.slab.x >= 1 - half - 0.002) {
            document.getElementById("stage").dispatchEvent(new PointerEvent("pointerdown", {
              clientX: 10, clientY: 10, pointerId: 1, pointerType: "touch",
              bubbles: true, cancelable: true
            }));
          }
        }, 8);
      JS

      expect(page).to have_css("#over.visible", wait: 40)

      messages = nil
      30.times do
        messages = page.evaluate_script("window.__arcadeMsgs")
        break if messages.any? { |m| m["type"] == "arcade:score" }
        sleep 0.1
      end

      scores = messages.select { |m| m["type"] == "arcade:score" }
      expect(scores.length).to eq(1)
      expect(scores.first["score"]).to eq(state["layers"])
    end
  end
end
