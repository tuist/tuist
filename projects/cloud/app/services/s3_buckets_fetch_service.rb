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

    class AccountNotFound < CloudError
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def message
        "Account with name #{name} was not found."
      end
    end
  end

  attr_reader :account_name, :user

  def initialize(account_name:, user:)
    super()
    @account_name = account_name
    @user = user
  end

  def call
    begin
      account = Account.find_by!(name: account_name)
    rescue ActiveRecord::RecordNotFound
      raise Error::AccountNotFound.new(account_name)
    end
    raise Error::Unauthorized.new(account_name) unless AccountPolicy.new(user, account).show?
    account.s3_buckets
  end
end
