# frozen_string_literal: true

class Organization < ApplicationRecord
  resourcify

  # Associations
  has_one :account, as: :owner, class_name: "Account", dependent: :destroy
  has_many :invitations, dependent: :destroy
  # Inspired from: https://github.com/RolifyCommunity/rolify/wiki/Usage#finding-roles-through-associations
  has_many :users,
    -> {
     where(roles: { name: :user }).where.not(roles: { name: :admin }) },
    through: :roles,
    class_name: "User",
    source: :users
  has_many :admins, -> { where(roles: { name: :admin }) }, through: :roles, class_name: "User", source: :users

  def name
    account.name
  end

  def pending_invitations
    invitations.where(accepted: false)
  end
end
