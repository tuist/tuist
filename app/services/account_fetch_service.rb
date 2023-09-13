# frozen_string_literal: true

class AccountFetchService < ApplicationService
  attr_reader :name

  module Error
    class AccountNotFound < CloudError
      attr_reader :name

      def initialize(name)
        super
        @name = name
      end

      def message
        "Account with name #{name} was not found."
      end
    end
  end

  def initialize(name:)
    @name = name
    super()
  end

  def call
    Account.find_by!(name: name)
  rescue ActiveRecord::RecordNotFound
    raise Error::AccountNotFound, name
  end
end
