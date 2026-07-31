# frozen_string_literal: true

# 2048 has a few rules that are easy to get subtly wrong, so they are pinned
# here against the real game code rather than a copy of it.

require "rails_helper"

RSpec.describe "2048 rules", type: :system do
  fab!(:player) { Fabricate(:user) }

  GAME_URL = "/plugins/discourse-arcade/games/twentyfortyeight/index.html"

  before do
    sign_in(player)
    visit GAME_URL
    expect(page).to have_css("#board")
    expect(page.evaluate_script("typeof window.Game2048")).to eq("object")
  end

  # One line of four, collapsed toward the direction of travel.
  def collapse(values)
    page.evaluate_script("window.Game2048.collapse(#{values.inspect})")
  end

  describe "merging a single line" do
    it "merges a pair and scores the merged value" do
      result = collapse([2, 2, 0, 0])
      expect(result["out"]).to eq([4, 0, 0, 0])
      expect(result["gained"]).to eq(4)
    end

    it "merges only the pair nearest the direction of travel" do
      result = collapse([2, 2, 4, 0])
      expect(result["out"]).to eq([4, 4, 0, 0])
      expect(result["gained"]).to eq(4)
    end

    it "merges the leading pair of three equal tiles, not all three" do
      result = collapse([2, 2, 2, 0])
      expect(result["out"]).to eq([4, 2, 0, 0])
      expect(result["gained"]).to eq(4)
    end

    it "lets each tile merge once per move, so four twos give two fours" do
      result = collapse([2, 2, 2, 2])
      expect(result["out"]).to eq([4, 4, 0, 0])
      expect(result["gained"]).to eq(8)
    end

    it "merges two different pairs in one move" do
      result = collapse([4, 4, 8, 8])
      expect(result["out"]).to eq([8, 16, 0, 0])
      expect(result["gained"]).to eq(24)
    end

    it "does not merge a tile that has already been merged into" do
      result = collapse([4, 2, 2, 4])
      expect(result["out"]).to eq([4, 4, 4, 0])
      expect(result["gained"]).to eq(4)
    end

    it "closes gaps without merging unequal tiles" do
      result = collapse([2, 0, 0, 4])
      expect(result["out"]).to eq([2, 4, 0, 0])
      expect(result["gained"]).to eq(0)
    end

    it "merges across a gap" do
      result = collapse([2, 0, 2, 4])
      expect(result["out"]).to eq([4, 4, 0, 0])
      expect(result["gained"]).to eq(4)
    end

    it "leaves an unmergeable line alone and scores nothing" do
      result = collapse([2, 4, 2, 4])
      expect(result["out"]).to eq([2, 4, 2, 4])
      expect(result["gained"]).to eq(0)
    end

    it "handles an empty line" do
      result = collapse([0, 0, 0, 0])
      expect(result["out"]).to eq([0, 0, 0, 0])
      expect(result["gained"]).to eq(0)
    end

    it "reaches 2048" do
      result = collapse([1024, 1024, 0, 0])
      expect(result["out"]).to eq([2048, 0, 0, 0])
      expect(result["gained"]).to eq(2048)
    end
  end

  describe "playing the board" do
    it "keeps the rules across hundreds of random moves" do
      # Merging never changes the total on the board, so after any move that
      # actually moved something the total may only grow by the one new tile.
      # Any off-by-one in the merge or spawn logic breaks this.
      report =
        page.evaluate_script(<<~JS)
          (function () {
            function state() {
              var cells = Array.prototype.map.call(
                document.querySelectorAll(".cell"),
                function (c) { return parseInt(c.dataset.v, 10); }
              );
              return {
                grid: cells,
                sum: cells.reduce(function (a, b) { return a + b; }, 0),
                tiles: cells.filter(function (v) { return v > 0; }).length,
                score: parseInt(document.getElementById("score").textContent, 10)
              };
            }

            function isPowerOfTwo(v) {
              return v >= 2 && (v & (v - 1)) === 0;
            }

            var dirs = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"];
            var problems = [];
            var moves = 0;
            var effective = 0;
            var noops = 0;
            var over = document.getElementById("over");

            while (moves < 400 && !over.classList.contains("visible")) {
              var before = state();

              window.dispatchEvent(
                new KeyboardEvent("keydown", {
                  key: dirs[Math.floor(Math.random() * 4)]
                })
              );
              moves++;

              var after = state();
              var changed = after.grid.join(",") !== before.grid.join(",");
              var scoreDelta = after.score - before.score;

              if (!changed) {
                noops++;
                if (scoreDelta !== 0) {
                  problems.push("score moved on a no-op move: " + scoreDelta);
                }
                continue;
              }

              effective++;

              var spawned = after.sum - before.sum;
              if (spawned !== 2 && spawned !== 4) {
                problems.push("board total grew by " + spawned + ", expected 2 or 4");
              }

              if (scoreDelta < 0 || scoreDelta % 4 !== 0) {
                problems.push("score delta " + scoreDelta + " is not a sum of merged tiles");
              }

              if (after.tiles > before.tiles + 1) {
                problems.push("tile count jumped from " + before.tiles + " to " + after.tiles);
              }

              var bad = after.grid.filter(function (v) {
                return v !== 0 && !isPowerOfTwo(v);
              });
              if (bad.length) {
                problems.push("non power of two tile: " + bad.join(","));
              }
            }

            return {
              moves: moves,
              effective: effective,
              noops: noops,
              finished: over.classList.contains("visible"),
              score: state().score,
              maxTile: Math.max.apply(null, state().grid),
              problems: problems
            };
          })()
        JS

      expect(report["problems"]).to eq([])
      expect(report["effective"]).to be > 50
      expect(report["score"]).to be > 0
      expect(report["maxTile"]).to be >= 16
    end

    it "starts with exactly two tiles, each a 2 or a 4" do
      tiles =
        page.evaluate_script(<<~JS)
          Array.prototype.map.call(
            document.querySelectorAll(".cell"),
            function (c) { return parseInt(c.dataset.v, 10); }
          ).filter(function (v) { return v > 0; })
        JS

      expect(tiles.length).to eq(2)
      expect(tiles).to all(satisfy { |v| [2, 4].include?(v) })
    end
  end
end
