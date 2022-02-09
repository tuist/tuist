# frozen_string_literal: true

class CacheController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :authenticate_user_from_token!

  def cache
    raise ActiveRecord::RecordNotFound
  end

  def upload_cache_artifact
    CacheArtifactUploadService.call(
      project_slug: params[:project_id],
      hash: params[:hash],
      name: params[:name],
      user: current_user
    )
  end

  def authenticate_user_from_token!
    authenticate_or_request_with_http_token do |token, options|
      user = User.find_by!(token: token)
      if user
        sign_in(user, store: false)
      end
    end
  end
end
