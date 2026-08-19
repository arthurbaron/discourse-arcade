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
#
# The card of fifteen is recitable on purpose and that cost the leaderboard its
# top: the sweep restarts at the same edge at the same speed every dart, so a
# player who learns the rhythm throws fifteen trebles out of fifteen, every
# time. 1150 was a wall, not a record. Sudden death is the answer, and the two
# properties it turns on are tested here: the card itself must stay bit-for-bit
# the game it was, or every score already on the board becomes incomparable, and
# the extra visits must get harder in a way that actually falls off, which a
# faster sweep alone does not do.

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

    # Found by reading the drawing code, then proved by counting pixels: the
    # second aim phase opened one path, added the horizontal line, and called
    # beginPath again for the landing dot, which discarded the line. The whole
    # vertical aim was played with a dot and no line. Measured on a 1120 pixel
    # row: 106 accent pixels broken, 1120 fixed. Nothing about "it reports a
    # score" could ever have caught this.
    it "draws the horizontal line across the board while aiming vertically" do
      result = page.evaluate_script(<<~JS)
        (function () {
          document.getElementById("stage").dispatchEvent(new PointerEvent("pointerdown", {
            clientX: 10, clientY: 10, pointerId: 1, pointerType: "touch",
            bubbles: true, cancelable: true
          }));

          return new Promise(function (resolve) {
            var tries = 0;
            function sample() {
              tries++;
              var s = window.Darts.state();
              var canvas = document.getElementById("view");
              var ctx = canvas.getContext("2d");
              var size = Math.min(canvas.width, canvas.height);

              // Sampling has to happen inside a frame that has actually been
              // drawn with the new phase; reading straight after the tap reads
              // the previous frame, which is how a first attempt at this
              // measurement fooled itself into passing.
              if (s.phase === "aimY" && s.sweep > -0.2 && s.sweep < 0.2) {
                var y = Math.round((0.53 + s.sweep * 0.38) * size);
                var row = ctx.getImageData(0, y, canvas.width, 1).data;
                var accent = 0;
                for (var i = 0; i < row.length; i += 4) {
                  if (row[i + 2] > row[i] + 40) { accent++; }
                }
                resolve({ accent: accent, width: canvas.width });
                return;
              }
              if (tries > 400) { resolve({ gaveUp: true }); return; }
              requestAnimationFrame(sample);
            }
            requestAnimationFrame(sample);
          });
        })();
      JS

      expect(result["gaveUp"]).to be_falsey
      # A full-width line, not just the landing dot and the board's own rings.
      expect(result["accent"]).to eq(result["width"])
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

    # Reported from play: three trebles in a row paid nothing, because they
    # crossed a visit boundary. The rule was right and completely invisible,
    # which is the same thing as wrong. These pin the state a player now has
    # on screen to reason about it.
    it "reports which visit is being thrown, and how far into it" do
      progress = ->(thrown) { page.evaluate_script("window.Darts.rules.visitProgress(#{thrown})") }

      expect(progress.call(0)).to include("visit" => 1, "visits" => 5, "thrownInVisit" => 0)
      expect(progress.call(1)).to include("visit" => 1, "thrownInVisit" => 1)

      # A finished visit stays the current one until the next dart is thrown,
      # which is what the board shows during the result pause.
      expect(progress.call(3)).to include("visit" => 1, "thrownInVisit" => 3)
      expect(progress.call(4)).to include("visit" => 2, "thrownInVisit" => 1)
      expect(progress.call(15)).to include("visit" => 5, "thrownInVisit" => 3)
    end

    it "telegraphs a live maximum once two trebles are in the same visit" do
      expect(state["maximumLive"]).to eq(false)

      page.execute_script(<<~JS)
        window.__watcher = setInterval(function () {
          var s = window.Darts.state();
          if (!s.alive || s.dartsThrown >= 2) { clearInterval(window.__watcher); return; }
          var target = s.phase === "aimX" ? 0 : -0.6059;
          if ((s.phase === "aimX" || s.phase === "aimY") && Math.abs(s.sweep - target) < 0.008) {
            document.getElementById("stage").dispatchEvent(new PointerEvent("pointerdown", {
              clientX: 10, clientY: 10, pointerId: 1, pointerType: "touch",
              bubbles: true, cancelable: true
            }));
          }
        }, 4);
      JS

      result = nil
      80.times do
        result = state
        break if result["dartsThrown"] >= 2
        sleep 0.2
      end

      expect(result["hits"].map { |h| h["label"] }).to eq(%w[T20 T20])
      expect(result["visitPoints"]).to eq([60, 60])
      expect(result["maximumLive"]).to eq(true)
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

  describe "the board staying readable" do
    # Fifteen throws at the twenty would bury the treble under white dots, so
    # darts come off the board the way they do at the oche: the current visit
    # stands full, the previous one fades, anything older is gone. At most six
    # dots ever show.
    it "fades the previous visit and removes everything older" do
      alpha = ->(index, total) { page.evaluate_script("window.Darts.rules.dartAlpha(#{index}, #{total})") }

      # Mid-run, eight darts thrown: darts 7-8 are the current visit (full),
      # 4-6 the previous (faded), 1-3 are off the board.
      expect(alpha.call(7, 8)).to eq(1)
      expect(alpha.call(6, 8)).to eq(1)
      expect(alpha.call(5, 8)).to eq(0.3)
      expect(alpha.call(3, 8)).to eq(0.3)
      expect(alpha.call(2, 8)).to eq(0)
      expect(alpha.call(0, 8)).to eq(0)

      # A freshly completed visit is still the current one until the next dart.
      expect(alpha.call(2, 3)).to eq(1)
      expect(alpha.call(0, 3)).to eq(1)

      # Never more than two visits' worth visible, at any point in the run.
      (1..15).each do |total|
        visible = (0...total).count { |i| alpha.call(i, total) > 0 }
        expect(visible).to be <= 6
      end
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
      # Blind taps cannot come near the sudden-death threshold, so this still
      # ends at fifteen. That is the point: only a near-perfect card continues.
      expect(final["total"]).to be < 1000
      expect(final["dartsThrown"]).to eq(15)
      expect(final["suddenDeath"]).to eq(false)
      expect(final["alive"]).to eq(false)

      # The total is the fifteen hits plus fifty per 180, an invariant that
      # holds whatever the blind taps happened to land on.
      expected = final["hits"].sum { |h| h["points"] } + final["bonuses180"] * 50
      expect(final["total"]).to eq(expected)
      expect(page).to have_css("#over.visible")
    end
  end

  describe "sudden death" do
    def extra_steps(visit)
      page.evaluate_script("window.Darts.rules.extraSweepSteps(#{visit})")
    end

    # The whole reason no scores need resetting. Every dart of the card runs at
    # the card's own sweep speed and starts from the same edge, so a score thrown
    # last month was thrown under exactly these rules.
    it "leaves the card of fifteen exactly as it was" do
      current = state
      expect(current["suddenDeath"]).to eq(false)
      expect(current["extraVisit"]).to eq(0)
      expect(current["sweepSteps"]).to eq(current["config"]["sweepSteps"])
      expect(current["sweepSteps"]).to eq(60)

      # And it is recitable: every position it can be frozen on lies on the grid
      # that starts at the far edge and steps by the card's own speed. Reading
      # the very first frame is a race (this asserted sweep == -range and caught
      # it three frames in), so this checks the invariant instead of the instant.
      range = current["config"]["range"]
      move = 2 * range / current["config"]["sweepSteps"]
      6.times do
        offset = (state["sweep"] + range) / move
        expect(offset - offset.round).to be_within(0.001).of(0)
        sleep 0.05
      end
    end

    it "only opens above a threshold no existing score reached" do
      expect(page.evaluate_script("window.Darts.rules.suddenDeathFrom()")).to eq(1000)
      expect(state["config"]["suddenDeathFrom"]).to eq(1000)
    end

    # A coarser grid of reachable stops is what makes an extra visit hard: fewer
    # of them land inside the treble ring at all. Measured on the fixed sweep,
    # coarser is NOT reliably harder, because whether a stop lands in the ring is
    # an alignment coincidence (30 steps leaves as much room as 60, while 36 and
    # 40 leave none). The random start in sudden death is what averages that
    # coincidence out, which is why both halves of the mechanic are needed.
    it "coarsens the grid visit by visit, down to a floor" do
      steps = (1..12).map { |v| extra_steps(v) }

      expect(steps.first).to be < 60
      expect(steps.each_cons(2).all? { |a, b| b <= a }).to eq(true)
      expect(steps.first).to be > steps[5]
      expect(steps.last).to eq(16)
      expect(extra_steps(50)).to eq(16)
    end

    # The property the fix exists for: the old maximum stops being a ceiling.
    # This drives a real perfect run rather than asserting about one, because the
    # only reason any of this is needed is that a real perfect run is achievable.
    it "carries a perfect card past the old maximum and still ends on its own" do
      page.execute_script(<<~JS)
        (function () {
          const stage = document.getElementById("stage");
          const TREBLE_MID = -(0.5824 + 0.6294) / 2;
          window.__seenSteps = [];
          window.__t = setInterval(function () {
            const s = window.Darts.state();
            if (!s.alive) { clearInterval(window.__t); window.__over = true; return; }
            if (s.phase === "result") { return; }
            if (window.__seenSteps.indexOf(s.sweepSteps) === -1) {
              window.__seenSteps.push(s.sweepSteps);
            }
            const move = (2 * s.config.range) / s.sweepSteps;
            const want = s.phase === "aimX" ? 0 : TREBLE_MID;
            if (Math.abs(s.sweep - want) <= move / 2) {
              stage.dispatchEvent(new PointerEvent("pointerdown", {
                clientX: 10, clientY: 10, pointerId: 1, pointerType: "touch",
                bubbles: true, cancelable: true
              }));
            }
          }, 4);
        })();
      JS

      # A perfect card is 1150 and always opens sudden death; how deep it then
      # goes varies, so this waits on the run ending rather than on a score.
      # Polls a flag rather than the whole state object: serialising every field
      # hundreds of times was most of this spec's runtime.
      600.times do
        break if page.evaluate_script("window.__over === true")
        sleep 0.1
      end

      final = state
      expect(final["alive"]).to eq(false)
      expect(final["suddenDeath"]).to eq(true)
      expect(final["dartsThrown"]).to be > 15
      expect(final["total"]).to be > 1150

      # Extra darts came in whole visits, and the run ended on one that was not a
      # maximum. That is the stopping rule, not a timeout.
      expect((final["dartsThrown"] - 15) % 3).to eq(0)
      last_visit = final["hits"].last(3).map { |h| h["points"] }
      expect(last_visit).not_to eq([60, 60, 60])

      # The grid really did coarsen as it went.
      seen = page.evaluate_script("window.__seenSteps")
      expect(seen.first).to eq(60)
      expect(seen.length).to be > 1
      expect(seen.max).to eq(60)

      # The total is still the hits plus fifty per maximum, sudden death included.
      expected = final["hits"].sum { |h| h["points"] } + final["bonuses180"] * 50
      expect(final["total"]).to eq(expected)
      expect(page).to have_css("#over.visible")
    end
  end
end
