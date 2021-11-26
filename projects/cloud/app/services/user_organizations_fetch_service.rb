# frozen_string_literal: true

class UserOrganizationsFetchService < ApplicationService
  def initialize(user:)
    super()
    @user = user
  end

  def call
    Organization.with_roles([:user, :admin], @user)
  end
end
