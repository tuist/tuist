# frozen_string_literal: true

class PagesController < ApplicationController
  def index
    render(component: 'pages/home')
  end
end
