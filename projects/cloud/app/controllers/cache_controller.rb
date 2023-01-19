# frozen_string_literal: true

class CacheController < APIController
  def cache
    # TODO: This should be removed eventually as it's only used to support older tuist versions.
    if request.head? && !cache_artifact_upload_service.object_exists?
      render(json: { message: "S3 object was not found", code: :not_found }, status: :not_found)
    else
      # TODO: Handle expires_at instead of hardcoded value
      render(json: { status: "success", data: { url: cache_artifact_upload_service.fetch, expires_at: 1000 } })
    end
  end

  def exists
    if cache_artifact_upload_service.object_exists?
      render(json: { status: "success", data: {} })
    else
      render(
        json: { errors: [{ message: "S3 object was not found", code: :not_found }], status: :not_found },
        status: :not_found)
    end
  end

  def upload_cache_artifact
    # TODO: Handle expires_at instead of hardcoded value
    render(json: { status: "success", data: { url: cache_artifact_upload_service.upload, expires_at: 1000 } })
  end

  def verify_upload
    render(json: { status: "success", data: { uploaded_size: cache_artifact_upload_service.verify_upload } })
  end

  private
    def cache_artifact_upload_service
      CacheService.new(
        project_slug: params[:project_id],
        hash: params[:hash],
        name: params[:name],
        user: current_user,
        project: @project,
      )
    end
end
