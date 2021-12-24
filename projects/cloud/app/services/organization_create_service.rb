# frozen_string_literal: true

class OrganizationCreateService < ApplicationService
  attr_reader :creator, :name

  def initialize(creator:, name:)
    super()
    @creator = creator
    @name = name
  end

  def call
    ActiveRecord::Base.transaction do
      organization = Organization.create!
      AccountCreateService.call(
        name: name,
        owner: organization
      )
      creator.add_role(:admin, organization)
      organization
    end
  end
end
