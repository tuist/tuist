# frozen_string_literal: true

module Mutations
  class DeleteProject < ::Mutations::BaseMutation
    argument :id, ID, required: true

    type Types::ProjectType

    def resolve(attributes)
      ProjectDeleteService.call(deleter: context[:current_user], **attributes)
    end
  end
end
