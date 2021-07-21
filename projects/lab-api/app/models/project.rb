# frozen_string_literal: true
class Project < ApplicationRecord
  # Concerns
  include TokenAuthenticatable

  # TokenAuthenticatable
  attr_authentication_token :api_token

  # Validations
  validates :name, presence: true, length: { maximum: 30, minimum: 5 }
  validates :repository_full_name, format: { with: %r{\A[\w.@\:-~]+/[\w.@\:-~]+\z}, message: "invalid organization/repo format" }

  # Associations
  belongs_to :account
end
