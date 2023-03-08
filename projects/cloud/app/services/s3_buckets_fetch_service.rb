# frozen_string_literal: true

class S3BucketsFetchService < ApplicationService
  module Error
    class Unauthorized < CloudError
      attr_reader :account_name

      def initialize(account_name)
        @account_name = account_name
      end

      def message
        "You do not have a permission to view buckets for an account #{account_name}"
      end
    end
  end

  attr_reader :account_name, :project_name, :user

  def initialize(account_name:, project_name:, user:)
    super()
    @account_name = account_name
    @project_name = project_name
    @user = user
  end

  def call
    account = AccountFetchService.call(name: account_name)
    raise Error::Unauthorized.new(account_name) unless AccountPolicy.new(user, account).show?

    account.s3_buckets.reject { |s3_bucket|
      s3_bucket.is_default && !s3_bucket.name.end_with?("#{account_name}-#{project_name}")
    }
  end
end
