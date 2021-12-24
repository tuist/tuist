# frozen_string_literal: true

class Project < ApplicationRecord
  # Associations
  belongs_to :account, optional: false

  # Validations
  validates :name, exclusion: Defaults.fetch(:blocklisted_slug_keywords)
end
