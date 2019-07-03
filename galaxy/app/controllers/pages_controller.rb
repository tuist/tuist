class PagesController < ApplicationController
  def index
    render component: "pages/home"
  end
end
