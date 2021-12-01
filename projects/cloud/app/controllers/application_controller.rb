# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit

  before_action :authenticate_user!

  def create_project
  end

  def show_project
  end

  def app
    render(layout: "app")
  end
end
