# frozen_string_literal: true
class Organization < ApplicationRecord
  resourcify

  # Associations
  has_one :account, dependent: :destroy, inverse_of: :owner, foreign_key: :owner_id
end
