# frozen_string_literal: true

# The contract spec only proves Intercept ends and reports a score, which it
# would do just as happily if tapping did nothing at all. These check the two
# things the game is actually about: a led shot destroys a missile, and firing
# costs ammo you then run out of.
#
# And, since players found it before any test did, the difficulty curve. Every
# knob used to flatten out by wave 26 while points per kill kept climbing with
# the wave number, so past roughly a quarter of a million points the game paid
# more and more for waves that never got harder. Nothing here could have caught
# that: a game that stops escalating still ends and still reports a score. So the
# curve is exposed as pure functions of the wave and walked directly.

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

  describe "the difficulty curve" do
    def curve(fn, wave)
      page.evaluate_script("window.Intercept.rules.#{fn}(#{wave})")
    end

    def peak
      page.evaluate_script("window.Intercept.rules.difficultyPeakWave()")
    end

    # The reported bug, as an assertion. Wave 30 is past every old ceiling, so if
    # the curve went flat again these would all be equal to wave 20.
    it "keeps asking for more long after the old ceilings" do
      expect(curve("waveMissiles", 30)).to be > curve("waveMissiles", 20)
      expect(curve("splitChance", 30)).to be > curve("splitChance", 20)
      expect(curve("spawnGap", 30)).to be < curve("spawnGap", 20)
      expect(curve("waveAmmo", 30)).to be < curve("waveAmmo", 20)

      # And still moving well beyond that.
      expect(curve("waveMissiles", 50)).to be > curve("waveMissiles", 30)
      expect(curve("waveAmmo", 50)).to be < curve("waveAmmo", 30)
    end

    # The pressure is the ratio of things to shoot at against shots to do it
    # with, which is what the game's own design note says it is about. Speed is
    # deliberately not the lever: it is held so the late game stays readable.
    it "raises the kills needed per shot, without speeding anything up" do
      demand = ->(w) do
        targets = curve("waveMissiles", w) * (1 + curve("splitChance", w))
        targets / curve("waveAmmo", w)
      end

      expect(demand.call(40)).to be > demand.call(20) * 2
      expect(demand.call(60)).to be > demand.call(40)

      # Speed stops climbing on purpose: past this, incoming fire would approach
      # the counter-missile's own speed and nothing could be reached in time.
      expect(curve("incomingSpeed", 60)).to eq(curve("incomingSpeed", 30))
    end

    # Everything a normal player sees has to be untouched. The complaint was
    # about the far end of the curve, not the game most people play.
    it "leaves the first twenty waves exactly as they were" do
      expected_missiles = (1..20).map { |w| [24, 6 + w * 2].min }
      expected_ammo = (1..20).map { |w| [20, 12 + w].min }
      expected_gap = (1..20).map { |w| [14, 52 - w * 3].max }

      expect((1..20).map { |w| curve("waveMissiles", w) }).to eq(expected_missiles)
      expect((1..20).map { |w| curve("waveAmmo", w) }).to eq(expected_ammo)
      expect((1..20).map { |w| curve("spawnGap", w) }).to eq(expected_gap)
      expect((3..20).map { |w| curve("splitChance", w) }).to all(be_within(0.0001).of(0.35))
    end

    # The self-check. A kill is worth more the higher the wave, which is right
    # while the waves are getting harder and wrong once they stop. If someone
    # retunes the curve so a knob moves past the peak without moving the peak,
    # paid endurance comes back silently. This is what fails instead.
    it "stops paying extra exactly where it stops getting harder" do
      peak_wave = peak

      %w[waveMissiles waveAmmo spawnGap splitChance].each do |fn|
        at_peak = curve(fn, peak_wave)
        expect(curve(fn, peak_wave + 20)).to eq(at_peak),
                                            "#{fn} still moves past wave #{peak_wave}, " \
                                            "so the score multiplier should not stop there"
      end

      # Rising up to the peak, flat after it.
      expect(curve("hitValue", peak_wave)).to be > curve("hitValue", peak_wave - 10)
      expect(curve("hitValue", peak_wave + 50)).to eq(curve("hitValue", peak_wave))
    end
  end
end
