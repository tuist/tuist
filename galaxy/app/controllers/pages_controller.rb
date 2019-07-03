class PagesController < ApplicationController
  def index
    render component: "pages/Home"
  end
end
