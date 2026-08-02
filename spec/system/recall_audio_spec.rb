# frozen_string_literal: true

# Recall shipped silent on iPhones. The context was created inside the opening
# gesture, which is enough for Chrome but not for Safari: Safari hands back a
# suspended context and leaves it there unless resume() is called. Desktop never
# showed it, so nothing here caught it.
#
# These drive the context into the state Safari leaves it in and check the game
# gets itself out of it, and that the label stops claiming there is sound while
# there is none.

require "rails_helper"

RSpec.describe "Recall audio", type: :system do
  fab!(:player) { Fabricate(:user) }

  let(:theme) do
    "bg=%23ffffff&fg=%23222222&accent=%230088cc&muted=%238f8f8f&low=%23e9e9e9"
  end

  before do
    sign_in(player)
    visit "/plugins/discourse-arcade/games/recall/index.html?#{theme}"
    expect(page).to have_css("#stage")

    # Catch the game's own context the first time it builds a note, since there
    # is no other handle on it from out here.
    page.execute_script(<<~JS)
      (function () {
        const proto = (window.AudioContext || window.webkitAudioContext).prototype;
        const real = proto.createOscillator;
        proto.createOscillator = function () {
          window.__ctx = this;
          return real.apply(this, arguments);
        };
      })();
    JS

    page.execute_script(<<~JS)
      document.getElementById("begin").dispatchEvent(
        new PointerEvent("pointerdown", { pointerId: 1, bubbles: true, cancelable: true })
      );
    JS
  end

  def audio_state
    page.evaluate_script("window.Recall.state().audio")
  end

  def label
    page.evaluate_script('document.getElementById("mute").textContent')
  end

  def tap_pad
    page.execute_script(<<~JS)
      document.getElementsByClassName("pad")[0].dispatchEvent(
        new PointerEvent("pointerdown", { pointerId: 1, bubbles: true, cancelable: true })
      );
    JS
  end

  def wait_until
    40.times do
      return true if yield
      sleep 0.1
    end
    false
  end

  it "runs after the opening tap" do
    expect(wait_until { audio_state == "running" }).to eq(true)
    expect(label).to eq("sound on")
  end

  it "recovers from the state Safari leaves the context in" do
    expect(wait_until { page.evaluate_script("!!window.__ctx") }).to eq(true)

    page.execute_script("window.__ctx.suspend();")
    expect(wait_until { audio_state == "suspended" }).to eq(true)

    # Silence has to be admitted, not papered over.
    expect(label).to eq("no sound")

    tap_pad

    expect(wait_until { audio_state == "running" }).to eq(true)
    # And reading the label right after asking must not lose the race: resume is
    # asynchronous, and an earlier attempt reported "no sound" while the sound
    # was already coming back.
    expect(wait_until { label == "sound on" }).to eq(true)
  end
end
