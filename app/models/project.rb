# frozen_string_literal: true

class Project < ApplicationRecord
  include TokenAuthenticatable

  # Token authenticatable
  autogenerates_token :token

  # Associations
  has_many :users, foreign_key: :last_visited_project_id, dependent: :nullify
  belongs_to :account, optional: false
  belongs_to :remote_cache_storage, polymorphic: true, optional: true

  # Validations
  validates :name, exclusion: Defaults.fetch(:blocklisted_slug_keywords)
end
