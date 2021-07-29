# frozen_string_literal: true
class OrganizationCreateService < ApplicationService
  attr_reader :name, :admin

  def initialize(name:, admin:)
    @name = name
    @admin = admin
    super()
  end

  def call
    ActiveRecord::Base.transaction do
      organization = Organization.new
      admin.add_role(:admin, organization)
      organization.save!
      AccountCreateService.call(owner: organization, name: name)
      organization
    end
  end
end
