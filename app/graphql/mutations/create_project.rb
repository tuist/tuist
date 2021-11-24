module Mutations
  class CreateProject < ::Mutations::BaseMutation
    argument :account_id, ID, required: true
    argument :name, String, required: true

    type Types::ProjectType

    def resolve(**attributes)
      Project.create!(**attributes, token: Devise.friendly_token.first(8))
    end
  end
end
