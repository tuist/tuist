module Mutations
  class ChangeUserRole < ::Mutations::BaseMutation
    argument :user_id, ID, required: true
    argument :organization_id, String, required: true
    argument :current_role, Types::RoleType, required: true
    argument :new_role, Types::RoleType, required: true

    type Types::UserType

    def resolve(attributes)
      ChangeUserRoleService.call(**attributes)
    end
  end
end
