# frozen_string_literal: true

class CacheClearService < ApplicationService
  module Error
    class Unauthorized < CloudError
      def message
        "You do not have a permission to clear this S3 bucket."
      end

      def status_code
        :unauthorized
      end
    end
  end

  attr_reader :project_slug, :subject

  def initialize(project_slug:, subject:)
    super()
    @project_slug = project_slug
    @subject = subject
  end

  def call
    project = ProjectFetchService.new.fetch_by_slug(
      slug: project_slug,
      subject: subject,
    )
    raise Error::Unauthorized unless ProjectPolicy.new(subject, project).update?

    s3_client, bucket_name = S3ClientService.call
    delete_objects(
      bucket_name: bucket_name,
      s3_client: s3_client,
      project: project,
    )
  end

  def delete_objects(s3_client:, bucket_name:, project:, marker: nil)
    objects_list = s3_client.list_objects(
      bucket: bucket_name,
      prefix: "#{project_slug}/",
    )
    if objects_list.contents.empty?
      return
    end

    s3_client.delete_objects(
      bucket: bucket_name,
      delete: {
        objects: objects_list.contents.map { |object| { key: object.key } },
      },
      marker: marker,
    )
    unless objects_list.next_marker.nil?
      delete_objects(
        s3_client: s3_client,
        project: project,
        marker: objects_list.next_marker,
      )
    end
  end
end
