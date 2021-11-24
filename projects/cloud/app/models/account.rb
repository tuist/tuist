# frozen_string_literal: true

class Account < ApplicationRecord
  BLOCKLISTED_NAMES = ["new", "project", "projects", "settings", "organization", "organizations"]

  # Associations
  belongs_to :owner, polymorphic: true, optional: false
  has_many :projects

  # Validations
  validates :name, exclusion: BLOCKLISTED_NAMES
end
