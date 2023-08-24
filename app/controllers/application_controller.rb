# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  before_action :authenticate_user!
  before_action :setup_self_hosting

  protect_from_forgery with: :null_session

  def app
    render(layout: 'app')
  end

  private

  def setup_self_hosting
    @self_hosted = Environment.self_hosted?
  end
end
