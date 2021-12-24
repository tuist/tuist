# frozen_string_literal: true

module Mutations
  class CreateProject < ::Mutations::BaseMutation
    argument :name, String, required: true
    argument :account_id, ID, required: false
    argument :organization_name, String, required: false

    type Types::ProjectType

    def resolve(attributes)
      ProjectCreateService.call(creator: context[:current_user], **attributes)
    end
  end
end
