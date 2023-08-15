# frozen_string_literal: true

class RootController < ApplicationController
  include Pundit::Authorization

  skip_before_action :authenticate_user!

  def app
    if current_user.nil?
      render(layout: "landing_page")
      return
    end
    authenticate_user!
    render(layout: "app")
  end

  def get_started
    render "get_started"
  end
end
