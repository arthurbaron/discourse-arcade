# frozen_string_literal: true

# Every game has to satisfy the same contract: load, be playable, and report
# exactly one whole-number score when the run ends. These specs drive each game
# to game over in a real browser and check that.

require "rails_helper"

RSpec.describe "Arcade games", type: :system do
  fab!(:player) { Fabricate(:user) }

  # A constant here would leak onto Object and clash with the other game spec.
  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before { sign_in(player) }

  # 2048 predates the shared shell in games/_shared and still uses its own
  # markup, so the stage element differs per game.
  def open_game(path, stage: "#stage")
    visit "/plugins/discourse-arcade/games/#{path}?#{theme}"

    # The game posts to its parent; standalone that is this same window.
    page.execute_script(<<~JS)
      window.__arcadeMsgs = [];
      window.addEventListener("message", function (e) {
        if (e.data && typeof e.data === "object" && e.data.type) {
          window.__arcadeMsgs.push(e.data);
        }
      });
    JS

    expect(page).to have_css(stage)
  end

  def expect_single_score
    expect(page).to have_css("#over.visible", wait: 60)

    messages = nil
    # The score message is posted in the same tick the overlay appears, but
    # delivery is a task later.
    30.times do
      messages = page.evaluate_script("window.__arcadeMsgs")
      break if messages.any? { |m| m["type"] == "arcade:score" }
      sleep 0.1
    end

    scores = messages.select { |m| m["type"] == "arcade:score" }
    expect(scores.length).to eq(1)

    value = scores.first["score"]
    expect(value).to be_a(Integer)
    expect(value).to be >= 0
    value
  end

  def stage_point(x_ratio, y_ratio)
    page.evaluate_script(<<~JS)
      (function () {
        var r = document.getElementById("stage").getBoundingClientRect();
        return { x: r.left + r.width * #{x_ratio}, y: r.top + r.height * #{y_ratio} };
      })()
    JS
  end

  def pointer(type, point, id = 1)
    page.execute_script(<<~JS)
      document.getElementById("stage").dispatchEvent(
        new PointerEvent("#{type}", {
          clientX: #{point["x"]},
          clientY: #{point["y"]},
          pointerId: #{id},
          pointerType: "touch",
          bubbles: true,
          cancelable: true
        })
      );
    JS
  end

  it "2048 reports a score when the board locks up" do
    open_game("twentyfortyeight/index.html", stage: "#board")

    page.execute_script(<<~JS)
      (function () {
        var dirs = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"];
        var over = document.getElementById("over");
        var moves = 0;
        while (moves < 5000 && !over.classList.contains("visible")) {
          window.dispatchEvent(
            new KeyboardEvent("keydown", { key: dirs[Math.floor(Math.random() * 4)] })
          );
          moves++;
        }
      })();
    JS

    expect(expect_single_score).to be > 0
  end

  it "Snake reports a score after running into the wall" do
    open_game("snake/index.html")

    # It starts moving right and nothing steers it, so it hits the wall. Food
    # spawns at random, so it may pick one up on the way: the score is whatever
    # it managed, the point is that exactly one arrives.
    expect(expect_single_score).to be >= 0
  end

  it "Breakout reports a score after losing every life" do
    open_game("breakout/index.html")

    # Park the paddle in the corner so the ball gets past it.
    pointer("pointerdown", stage_point(0.03, 0.95))

    expect(expect_single_score).to be >= 0
  end

  it "Keepie Uppie reports a score when the ball is left to drop" do
    open_game("keepie/index.html")

    # No taps, so the opening kick-up falls straight to the floor.
    expect(expect_single_score).to eq(0)
  end

  it "Dribble reports a score after running into a defender" do
    open_game("dribble/index.html")

    # Sweep across the pitch so it meets a defender quickly instead of waiting
    # for one to happen to line up with a stationary player.
    page.execute_script(<<~JS)
      (function () {
        var stage = document.getElementById("stage");
        var r = stage.getBoundingClientRect();
        var at = 0;
        setInterval(function () {
          at = at === 0 ? 1 : 0;
          stage.dispatchEvent(new PointerEvent("pointermove", {
            clientX: r.left + r.width * (0.08 + at * 0.84),
            clientY: r.top + r.height * 0.85,
            pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
          }));
        }, 160);
      })();
    JS

    expect(expect_single_score).to be >= 0
  end

  it "Hold the Line reports a score when the formation is left alone" do
    open_game("holdtheline/index.html")

    # Firing is automatic, so a motionless player still shoots. It ends either
    # by taking three hits or by the formation reaching the line.
    expect(expect_single_score).to be >= 0
  end

  it "Recall counts the rounds repeated before a wrong pad" do
    open_game("recall/index.html")

    # Pads flash rather than sit still, so a spec reads the sequence and plays it
    # back. Three rounds correctly, then a deliberately wrong pad.
    page.execute_script(<<~JS)
      (function () {
        const TARGET = 3;
        const pads = document.getElementsByClassName("pad");

        function tap(el) {
          el.dispatchEvent(new PointerEvent("pointerdown", {
            pointerId: 1, pointerType: "touch", bubbles: true, cancelable: true
          }));
        }

        tap(document.getElementById("begin"));

        function tick() {
          const s = window.Recall.state();
          if (s.phase === "over") { return; }

          if (s.phase === "input") {
            if (s.score >= TARGET) {
              // Anything other than the pad it wants.
              tap(pads[(s.sequence[s.expected] + 1) % 4]);
              return;
            }
            for (let i = s.expected; i < s.sequence.length; i++) {
              tap(pads[s.sequence[i]]);
            }
          }

          setTimeout(tick, 60);
        }

        setTimeout(tick, 60);
      })();
    JS

    expect(expect_single_score).to eq(3)
  end

  it "Intercept reports a score once every city is gone" do
    open_game("intercept/index.html")

    # No taps at all, so the waves land unopposed until the last city falls.
    expect(expect_single_score).to be >= 0
  end

  it "Debris reports a score when the ship is flown into the rocks" do
    open_game("debris/index.html")

    # A stationary ship auto-fires and clears the rocks that would have hit it,
    # so waiting for a collision can take forever. Steer at the nearest rock
    # instead, which also exercises the real steering and collision code.
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

        // Press once and then only re-aim. Re-pressing would restart the
        // hold timer every time, and a tap turns without thrusting, so the ship
        // would steer beautifully and never actually go anywhere.
        let pressed = false;

        setInterval(function () {
          const s = window.Debris.state();
          if (!s.rocks.length) { return; }

          let best = s.rocks[0];
          let bestD = Infinity;
          s.rocks.forEach(function (rock) {
            const d = Math.hypot(rock.x - s.ship.x, rock.y - s.ship.y);
            if (d < bestD) { bestD = d; best = rock; }
          });

          if (!pressed) {
            pressed = true;
            send("pointerdown", best.x, best.y);
          }
          send("pointermove", best.x, best.y);
        }, 120);
      })();
    JS

    expect(expect_single_score).to be >= 0
  end

  it "Penalty reports a score after three shots over the bar" do
    open_game("penalty/index.html")

    ball = stage_point(0.5, 0.87)
    over_the_bar = stage_point(0.5, 0.04)

    3.times do |i|
      pointer("pointerdown", ball, i + 1)
      pointer("pointermove", over_the_bar, i + 1)
      pointer("pointerup", over_the_bar, i + 1)
      sleep 1.4 # flight plus the result pause
    end

    expect(expect_single_score).to eq(0)
  end
end
