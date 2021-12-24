# frozen_string_literal: true

class OrganizationFetchService < ApplicationService
  attr_reader :name

  def initialize(name:)
    super()
    @name = name
  end

  def call
    Account.find_by(name: name).owner
  end
end
