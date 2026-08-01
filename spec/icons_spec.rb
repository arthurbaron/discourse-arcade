# frozen_string_literal: true

require "rails_helper"

RSpec.describe SvgSprite do
  before { SiteSetting.arcade_enabled = true }

  # gamepad is registered by the plugin but rendered nowhere in it, which makes
  # it look like dead code. It is not: an admin picks it for the sidebar link to
  # /arcade, and sidebar link icons are not one of the sources that fill the
  # sprite. Removing the registration empties the icon out of the sprite and the
  # sidebar link silently loses its glyph. That has already happened once.
  it "keeps the arcade icons in the sprite" do
    icons = described_class.all_icons

    expect(icons).to include("gamepad")
    expect(icons).to include("star")
    expect(icons).to include("trophy")
  end
end
