# frozen_string_literal: true

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
