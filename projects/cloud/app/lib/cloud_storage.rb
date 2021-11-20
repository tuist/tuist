# frozen_string_literal: true

require "google/cloud/storage"

class CloudStorage
  attr_reader :storage

  def initialize(
    key: Rails.application.credentials.gcs[:credentials]
  )
    @storage = Google::Cloud::Storage.new(
      project_id: key[:project_id],
      credentials: key
    )
  end
end
