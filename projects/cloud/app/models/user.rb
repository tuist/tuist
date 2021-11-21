# frozen_string_literal: true

class User < ApplicationRecord
  rolify

  # Devise
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable,
    :lockable, :timeoutable, :trackable,
    :omniauthable,
    omniauth_providers: [:github, :gitlab]

  # Associations
  has_one :account, as: :owner, inverse_of: :owner, dependent: :destroy

  def avatar_url
    hash = Digest::MD5.hexdigest(email.downcase)
    "https://www.gravatar.com/avatar/#{hash}"
  end

  def projects
    UserProjectsFetchService.call(user: self)
  end
end
