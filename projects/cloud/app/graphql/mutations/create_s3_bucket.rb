# frozen_string_literal: true

module Mutations
  class CreateS3Bucket < ::Mutations::BaseMutation
    argument :name, String, required: true
    argument :access_key_id, String, required: true
    argument :secret_access_key, String, required: true
    argument :region, String, required: true
    argument :account_id, ID, required: true

    type Types::S3BucketType

    def resolve(attributes)
      S3BucketCreateService.call(**attributes)
    end
  end
end
