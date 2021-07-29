# frozen_string_literal: true
class AppController < ApplicationController
  include Authenticatable
  before_action :authenticate_authenticatable!

  def index
    render(component: "App", prerender: false)
  end
end
