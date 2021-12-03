# frozen_string_literal: true

class ProjectFetchService < ApplicationService
  module Error
    Unauthorized = Class.new(StandardError)
  end

  attr_reader :name, :account_name, :user

  def initialize(name:, account_name:, user:)
    super()
    @name = name
    @account_name = account_name
    @user = user
  end

  def call
    account = Account.find_by(name: account_name)
    project = Project.find_by(account_id: account.id, name: name)
    raise Error::Unauthorized unless ProjectPolicy.new(user, project).show?
    project
  end
end
