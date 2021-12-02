class ProjectPolicy < ApplicationPolicy
  def show?
    if record.account.owner_type == "User"
      return record.account.owner_id == user.id
    end
    organization = Organization.find(record.account.owner_id)
    OrganizationPolicy.new(user, organization).show?
  end
end
