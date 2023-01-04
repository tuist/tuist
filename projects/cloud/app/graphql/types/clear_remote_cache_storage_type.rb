# frozen_string_literal: true

module Types
  class ClearRemoteCacheStorageType < Types::BaseObject
    field :bucket, Types::S3BucketType
    field :errors, [Types::UserError], null: false
  end
end
