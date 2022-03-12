# frozen_string_literal: true

class AccountPolicy < ApplicationPolicy
  def show?
    if record.owner_type == "User"
      return record.owner_id == user.id
    end

    organization = Organization.find(record.owner_id)
    OrganizationPolicy.new(user, organization).show?
  end

  def update?
    if record.owner_type == "User"
      return record.owner_id == user.id
    end

    organization = Organization.find(record.owner_id)
    OrganizationPolicy.new(user, organization).update?
  end
end
