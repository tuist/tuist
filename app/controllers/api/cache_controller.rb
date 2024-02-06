# frozen_string_literal: true
# typed: true

module API
  class CacheController < APIController
    def show
      # TODO: This should be removed eventually as it's only used to support older tuist versions.
      if request.head? && !cache_service.object_exists?
        render(json: { message: "S3 object was not found", code: :not_found }, status: :not_found)
      else
        # TODO: Handle expires_at instead of hardcoded value
        render(json: { status: "success", data: { url: cache_service.fetch, expires_at: 1000 } })
      end
    end

    def exists
      if cache_service.object_exists?
        render(json: { status: "success", data: {} })
      else
        render(
          json: { errors: [{ message: "S3 object was not found", code: :not_found }], status: :not_found },
          status: :not_found,
        )
      end
    end

    def upload_cache_artifact
      # TODO: Handle expires_at instead of hardcoded value
      render(json: { status: "success", data: { url: cache_service.upload, expires_at: 1000 } })
    end

    def multipart_upload_cache_artifact_start
      render(json: { status: "success", data: { upload_id: cache_service.multipart_upload_start } })
    end

    def multipart_upload_cache_artifact_generate_url
      upload_id = params[:upload_id]
      part_number = params[:part_number]
      render(json: {
        status: "success",
        data: {
          url: cache_service.multipart_generate_url(
            upload_id: upload_id,
            part_number: part_number.to_i,
          ),
        },
      })
    end

    def multipart_upload_cache_artifact_complete
      parts_params = params.permit(parts: [:etag, :part_number])
      parts = parts_params[:parts].map do |part|
        { part_number: part[:part_number], etag: part[:etag] }
      end
      upload_id = params[:upload_id]
      cache_service.multipart_upload_complete(upload_id: upload_id, parts: parts)
      render(json: {
        status: "success",
        data: {},
      })
    end

    def verify_upload
      render(json: { status: "success", data: { uploaded_size: cache_service.verify_upload } })
    end

    def clean
      CacheClearService.call(
        project_slug: "#{params[:account_name]}/#{params[:project_name]}",
        subject: current_subject,
      )
    end

    private

    def cache_service
      CacheService.new(
        project_slug: params[:project_id],
        cache_category: params[:cache_category],
        hash: params[:hash],
        name: params[:name],
        subject: current_subject,
        add_cloud_warning: ->(message) { response.set_header('x-cloud-warning', message) },
      )
    end
  end
end
