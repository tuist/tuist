# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit

  before_action :authenticate_user!

  def app
    render(layout: "app")
  end
end
