# frozen_string_literal: true

class AccountPolicy < ApplicationPolicy
  def show?
    if subject.is_a?(User)
      if record.owner_type == "User"
        return record.owner_id == subject.id
      end

      organization = Organization.find(record.owner_id)
      OrganizationPolicy.new(subject, organization).show?
    else
      false
    end
  end

  def update?
    if subject.is_a?(User)
      if record.owner_type == "User"
        return record.owner_id == subject.id
      end

      organization = Organization.find(record.owner_id)
      OrganizationPolicy.new(subject, organization).update?
    else
      false
    end
  end
end
