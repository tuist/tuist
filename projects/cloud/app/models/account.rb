# frozen_string_literal: true

class Account < ApplicationRecord
  # Associations
  belongs_to :owner, polymorphic: true, optional: false
  has_many :projects

  # Validations
  validates :name, exclusion: Defaults.fetch(:blocklisted_slug_keywords)
end
