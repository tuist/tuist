# frozen_string_literal: true

class Project < ApplicationRecord
  include TokenAuthenticatable

  # Token authenticatable
  autogenerates_token :token

  # Associations
  belongs_to :account, optional: false

  # Validations
  validates :name, exclusion: Defaults.fetch(:blocklisted_slug_keywords)
end
