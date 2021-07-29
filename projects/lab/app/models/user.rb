# typed: ignore
# frozen_string_literal: true

class User < ApplicationRecord
  # Roles
  rolify

  # Devise
  devise :database_authenticatable,
    :registerable,
    :recoverable,
    :rememberable,
    :validatable,
    # :confirmable,
    :lockable,
    :timeoutable,
    :trackable,
    :omniauthable,
    omniauth_providers: [:github]

  # Associations
  has_one :account, dependent: :destroy, inverse_of: :owner, foreign_key: :owner_id
  has_many :authorizations, dependent: :destroy

  def avatar_url
    hash = Digest::MD5.hexdigest(email.downcase)
    "https://www.gravatar.com/avatar/#{hash}"
  end
end
