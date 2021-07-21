# frozen_string_literal: true
class Account < ApplicationRecord
  # Validations
  validates :name, presence: true, length: { maximum: 30, minimum: 5 }, uniqueness: true, format: { with: /\A[a-zA-Z\-\_]+\z/, message: "invalid account name" }
  validates :owner_id, uniqueness: { scope: :owner_type }

  # Associations
  belongs_to :owner, inverse_of: :account, polymorphic: true, dependent: :destroy
  has_many :projects, dependent: :destroy
end
