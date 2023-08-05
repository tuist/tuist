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

  def as_json(options = {})
    members = []
    members
    .concat(
      admins.map { |admin| OrganizationMember.new(id: admin.id, name: admin.account.name, email: admin.email, role: :admin) }
    )
    .concat(
      users.map { |user| OrganizationMember.new(id: user.id, name: user.account.name, email: user.email, role: :user) }
    )
    super(options.merge(only: [:id])).merge({ name: name, members: members, invitations: invitations })
  end
end

class OrganizationMember
  attr_reader :id, :name, :email, :role

  def initialize(id:, name:, email:, role:)
    @id = id
    @name = name
    @email = email
    @role = role
  end

  def as_json()
    {
      id: id,
      name: name,
      email: email,
      role: role
    }
  end
end
