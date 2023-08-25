# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization

  before_action :authenticate_user!
  before_action :setup_variables

  protect_from_forgery with: :null_session

  def app
    if current_user.legacy?
      render(layout: 'app')
    else
      render 'get_started'
    end
  end

  def get_started
    render 'get_started'
  end

  private

  def setup_variables
    @self_hosted = Environment.self_hosted?
    @current_user = current_user
  end
end
