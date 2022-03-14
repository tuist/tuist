# frozen_string_literal: true

module Mutations
  class UpdateS3Bucket < ::Mutations::BaseMutation
    argument :id, ID, required: true
    argument :name, String, required: true
    argument :access_key_id, String, required: true
    argument :secret_access_key, String, required: true
    argument :region, String, required: true

    type Types::S3BucketType

    def resolve(attributes)
      S3BucketUpdateService.call(**attributes, user: context[:current_user])
    end
  end
end
