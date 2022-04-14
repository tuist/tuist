# frozen_string_literal: true

module Mutations
  class UpdateLastVisitedProject < ::Mutations::BaseMutation
    argument :id, ID, required: true

    type Types::UserType

    def resolve(attributes)
      LastVisitedProjectUpdateService.call(user: context[:current_user], **attributes)
    end
  end
end
