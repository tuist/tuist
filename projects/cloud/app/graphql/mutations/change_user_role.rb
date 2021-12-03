module Mutations
  class ChangeUserRole < ::Mutations::BaseMutation
    argument :user_id, ID, required: true
    argument :organization_id, String, required: true
    argument :role, Types::RoleType, required: true

    type Types::UserType

    def resolve(attributes)
      begin
        ChangeUserRoleService.call(**attributes, acting_user: context[:current_user])
      rescue ChangeUserRoleService::Error::Unauthorized
        raise GraphQL::ExecutionError, "You do not have a permission to change a role for this user."
      end
    end
  end
end
