# frozen_string_literal: true

class ProjectChangeRemoteCacheStorageService < ApplicationService
  attr_reader :id, :user, :project_id

  module Error
    class S3BucketNotFound < CloudError
      attr_reader :id

      def initialize(id)
        @id = id
      end

      def message
        "S3 bucket with id #{id} was not found."
      end
    end

    class ProjectNotFound < CloudError
      attr_reader :id

      def initialize(id)
        @id = id
      end

      def message
        "Project with id #{id} was not found."
      end
    end

    class Unauthorized < CloudError
      attr_reader :account_name

      def initialize(account_name)
        @account_name = account_name
      end

      def message
        "You are not allowed to edit account #{account_name}."
      end
    end
  end

  def initialize(id:, project_id:, user:)
    super()
    @id = id
    @project_id = project_id
    @user = user
  end

  def call
    begin
      s3_bucket = S3Bucket.find(id)
    rescue ActiveRecord::RecordNotFound
      raise Error::S3BucketNotFound.new(id)
    end

    raise Error::Unauthorized.new(s3_bucket.account.name) unless AccountPolicy.new(user, s3_bucket.account).update?

    begin
      project = Project.find(project_id)
    rescue ActiveRecord::RecordNotFound
      raise Error::ProjectNotFound.new(project_id)
    end

    project.update(remote_cache_storage: s3_bucket)
    s3_bucket
  end
end
