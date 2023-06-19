# frozen_string_literal: true

module Mutations
  class ChangeRemoteCacheStorage < ::Mutations::BaseMutation
    argument :id, ID, required: false
    argument :project_id, ID, required: true

    def resolve(attributes)
      ProjectChangeRemoteCacheStorageService.call(**attributes, user: context[:current_user])
    end
  end
end
