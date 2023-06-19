# frozen_string_literal: true

module Types
  class ProjectType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :account, AccountType, null: false
    field :slug, String, null: false
    field :remote_cache_storage, RemoteCacheStorageType, null: true
    field :token, String, null: false

    def slug
      "#{object.account.name}/#{object.name}"
    end

    def remote_cache_storage
      puts "Get remote_cache_storage for #{object.remote_cache_storage}"
      if object.remote_cache_storage.is_a?(DefaultS3Bucket)
        puts "Return nil"
        nil
      else
        object.remote_cache_storage
      end
    end
  end
end
