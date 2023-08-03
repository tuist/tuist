# frozen_string_literal: true

class ProjectDeleteService < ApplicationService
  module Error
    class Unauthorized < CloudError
      def status_code
        :unauthorized
      end

      def message
        "You do not have a permission to delete this project."
      end
    end

    class ProjectNotFound < CloudError
      attr_reader :id

      def initialize(id)
        @id = id
      end

      def status_code
        :not_found
      end

      def message
        "Project with id #{id} was not found."
      end
    end
  end

  attr_reader :id, :deleter

  def initialize(id:, deleter:)
    super()
    @id = id
    @deleter = deleter
  end

  def call
    project = ProjectFetchService.new.fetch_by_id(project_id: id, user: deleter)

    raise Error::Unauthorized.new unless ProjectPolicy.new(deleter, project).update?
    project.destroy
  end

  def s3_client
    Aws::S3::Client.new(
      region: "eu-west-1",
      access_key_id: Rails.application.credentials.aws[:access_key_id],
      secret_access_key: Rails.application.credentials.aws[:secret_access_key],
    )
  end
end
