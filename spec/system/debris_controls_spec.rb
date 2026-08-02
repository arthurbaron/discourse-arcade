# frozen_string_literal: true

# Debris felt stiff to turn with the keyboard. The cause was that the game
# nudged the heading once per keydown, so holding a key leaned on the operating
# system's key repeat: one turn, roughly half a second of nothing, then a burst.
# No amount of tuning the turn rate fixes that, because the input itself arrives
# in lumps.
#
# It now tracks which keys are down and turns on every step. That is a property a
# spec can check, and no amount of playing it in a hidden browser tab can, since
# requestAnimationFrame does not run there and nothing moves at all.

require "rails_helper"

RSpec.describe "Debris controls", type: :system do
  fab!(:player) { Fabricate(:user) }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before do
    sign_in(player)
    visit "/plugins/discourse-arcade/games/debris/index.html?#{theme}"
    expect(page).to have_css("#stage")
  end

  def hold(key)
    page.execute_script(
      "window.dispatchEvent(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));",
    )
  end

  def release(key)
    page.execute_script(
      "window.dispatchEvent(new KeyboardEvent('keyup', { key: '#{key}', bubbles: true }));",
    )
  end

  def sample_headings(count, gap: 0.05)
    Array.new(count) do
      value = page.evaluate_script("window.Debris.state().ship.heading")
      sleep gap
      value
    end
  end

  it "turns continuously while a key is held, not in bursts" do
    hold("ArrowLeft")
    headings = sample_headings(18)
    release("ArrowLeft")

    deltas = headings.each_cons(2).map { |a, b| (b - a).abs }
    turning = deltas.count { |d| d > 0.001 }

    # The old behaviour left a long dead stretch at the start while the operating
    # system waited to begin repeating, so most samples showed no movement.
    expect(turning).to be >= (deltas.length * 0.8).floor
    expect((headings.last - headings.first).abs).to be > 2.0
  end

  it "stops turning the moment the key is released" do
    hold("ArrowRight")
    sleep 0.3
    release("ArrowRight")

    sleep 0.1
    settled = page.evaluate_script("window.Debris.state().ship.heading")
    sleep 0.4

    expect(page.evaluate_script("window.Debris.state().ship.heading")).to be_within(
      0.01,
    ).of(settled)
  end

  it "thrusts while the up key is held and coasts after it" do
    expect(page.evaluate_script("window.Debris.state().thrusting")).to eq(false)

    hold("ArrowUp")
    sleep 0.2
    expect(page.evaluate_script("window.Debris.state().thrusting")).to eq(true)

    release("ArrowUp")
    sleep 0.1
    expect(page.evaluate_script("window.Debris.state().thrusting")).to eq(false)
  end
end
