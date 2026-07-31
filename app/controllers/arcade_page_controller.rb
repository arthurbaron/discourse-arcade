# frozen_string_literal: true

# Boots the Ember app for /arcade and /arcade/g/:slug.
class ArcadePageController < ApplicationController
  requires_login

  def index
    render html: "".html_safe, layout: "application"
  end
end
