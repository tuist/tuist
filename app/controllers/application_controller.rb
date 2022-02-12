# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit

  before_action :authenticate_user!
  protect_from_forgery with: :null_session

  def app
    render(layout: "app")
  end
end
