# frozen_string_literal: true

class ProjectsController < ApplicationController
  def show
    redirect_to("/#{params[:account_name]}/#{params[:project_name]}/analytics")
  end
end
