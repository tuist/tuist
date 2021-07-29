# frozen_string_literal: true
class Authorization < ApplicationRecord
  # include Encryptable
  # attr_encrypted :token, :secret, :refresh_token

  belongs_to :user, optional: true
  validates :uid, uniqueness: { scope: [:provider] }
end
