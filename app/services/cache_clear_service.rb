# frozen_string_literal: true

class CacheClearService < ApplicationService
  module Error
    class Unauthorized < CloudError
      def message
        "You do not have a permission to clear this S3 bucket."
      end

      def status
        :unauthorized
      end
    end
  end

  attr_reader :project_slug, :clearer

  def initialize(project_slug:, clearer:)
    super()
    @project_slug = project_slug
    @clearer = clearer
  end

  def call
    project = ProjectFetchService.new.fetch_by_slug(
      slug: project_slug,
      user: clearer,
    )
    s3_bucket = project.remote_cache_storage
    raise Error::Unauthorized.new unless ProjectPolicy.new(clearer, project).update?

    s3_client = S3ClientService.call(s3_bucket: s3_bucket)
    delete_objects(
      s3_client: s3_client,
      project: project,
    )

    if s3_bucket.is_a?(DefaultS3Bucket)
      nil
    else
      s3_bucket
    end
  end

  def delete_objects(s3_client:, project:, marker: nil)
    objects_list = s3_client.list_objects(
      bucket: project.remote_cache_storage.name,
      prefix: "#{project_slug}/",
    )
    if objects_list.contents.empty?
      return
    end
    s3_client.delete_objects(
      bucket: project.remote_cache_storage.name,
      delete: {
        objects: objects_list.contents.map { |object| { key: object.key } },
      },
      marker: marker,
    )
    if !objects_list.next_marker.nil?
      delete_objects(
        s3_client: s3_client,
        project: project,
        marker: objects_list.next_marker,
      )
    end
  end
end
