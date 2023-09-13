# frozen_string_literal: true

module Mutations
  class ClearRemoteCacheStorage < ::Mutations::BaseMutation
    argument :project_slug, String, required: true

    type Types::ClearRemoteCacheStorageType

    def resolve(attributes)
      bucket = CacheClearService.call(clearer: context[:current_user], **attributes)
      {
        bucket: bucket,
        errors: [],
      }
    rescue CloudError => error
      {
        bucket: nil,
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
