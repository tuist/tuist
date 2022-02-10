# frozen_string_literal: true

class CacheController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :authenticate_user_from_token!

  def cache
    if request.head? && !cache_artifact_upload_service.object_exists?
      render(json: { message: "S3 object was not found", code: :not_found }, status: :not_found)
    else
      render(json: { status: "success", data: { url: cache_artifact_upload_service.fetch, expires_at: 1000 } })
    end
  end

  def upload_cache_artifact
    render(json: { status: "success", data: { url: cache_artifact_upload_service.upload, expires_at: 1000 } })
  end

  def verify_upload
    render(json: { status: "success", data: { uploaded_size: cache_artifact_upload_service.verify_upload } })
  end

  def authenticate_user_from_token!
    authenticate_or_request_with_http_token do |token, options|
      user = User.find_by!(token: token)
      if user
        sign_in(user, store: false)
      end
    end
  end

  private
  def cache_artifact_upload_service
    CacheArtifactUploadService.new(
      project_slug: params[:project_id],
      hash: params[:hash],
      name: params[:name],
      user: current_user,
    )
  end
end
