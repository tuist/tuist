# frozen_string_literal: true

class Organization < ApplicationRecord
  after_update :update_subscription_after_roles_update, if: :saved_change_to_roles?
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

  def update_subscription_after_roles_update
    subscription = Stripe::Subscription.list({
      limit: 1,
      customer: invitation.organization.account.customer_id,
    }).first
    Stripe::Subscription.update(
      subscription.id,
      {
        items: [
          {
            price: subscription.items.data.first.price.id,
            quantity: admins.count + users.count,
          },
        ],
      },
    )
  end
end
