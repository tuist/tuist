# frozen_string_literal: true

module Mutations
  class CreateProject < ::Mutations::BaseMutation
    argument :name, String, required: true
    argument :account_id, ID, required: false
    argument :organization_name, String, required: false

    type Types::CreateProjectType

    def resolve(attributes)
      begin
        project = ProjectCreateService.call(creator: context[:current_user], **attributes)
        {
          project: project,
          errors: [],
        }
      rescue CloudError => error
        {
          project: nil,
          errors: [
            {
              message: error.message,
              path: [**attributes],
            },
          ],
        }
      end
    end
  end
end
