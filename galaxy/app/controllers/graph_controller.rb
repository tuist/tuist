# frozen_string_literal: true

class GraphController < ApplicationController
  def show
    render("components/pages/graph/show")
  end
end
