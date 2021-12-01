# frozen_string_literal: true

class User < ApplicationRecord
  rolify

  delegate :can?, :cannot?, to: :ability

  # Devise
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable,
    :lockable, :timeoutable, :trackable,
    :omniauthable,
    omniauth_providers: [:github, :gitlab]

  # Associations
  has_one :account, as: :owner, inverse_of: :owner, dependent: :destroy
  belongs_to :last_visited_project, class_name: "Project", optional: true

  def avatar_url
    hash = Digest::MD5.hexdigest(email.downcase)
    "https://www.gravatar.com/avatar/#{hash}"
  end

  def projects
    UserProjectsFetchService.call(user: self)
  end

  def accounts
    UserAccountsFetchService.call(user: self)
  end

  def ability
    @ability ||= Ability.new(self)
  end
end
