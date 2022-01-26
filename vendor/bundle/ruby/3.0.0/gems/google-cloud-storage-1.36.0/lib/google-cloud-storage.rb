# Copyright 2016 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

##
# This file is here to be autorequired by bundler, so that the
# Google::Cloud.storage and Google::Cloud#storage methods can be available, but
# the library and all dependencies won't be loaded until required and used.


gem "google-cloud-core"
require "google/cloud" unless defined? Google::Cloud.new
require "google/cloud/config"
require "googleauth"

module Google
  module Cloud
    ##
    # Creates a new object for connecting to the Storage service.
    # Each call creates a new connection.
    #
    # For more information on connecting to Google Cloud see the
    # {file:AUTHENTICATION.md Authentication Guide}.
    #
    # @see https://cloud.google.com/storage/docs/authentication#oauth Storage
    #   OAuth 2.0 Authentication
    #
    # @param [String, Array<String>] scope The OAuth 2.0 scopes controlling the
    #   set of resources and operations that the connection can access. See
    #   [Using OAuth 2.0 to Access Google
    #   APIs](https://developers.google.com/identity/protocols/OAuth2).
    #
    #   The default scope is:
    #
    #   * `https://www.googleapis.com/auth/devstorage.full_control`
    # @param [Integer] retries Number of times to retry requests on server
    #   error. The default value is `3`. Optional.
    # @param [Integer] timeout (default timeout) The max duration, in seconds, to wait before timing out. Optional.
    #    If left blank, the wait will be at most the time permitted by the underlying HTTP/RPC protocol.
    # @param [Integer] open_timeout How long, in seconds, before failed connections time out. Optional.
    # @param [Integer] read_timeout How long, in seconds, before requests time out. Optional.
    # @param [Integer] send_timeout How long, in seconds, before receiving response from server times out. Optional.
    #
    # @return [Google::Cloud::Storage::Project]
    #
    # @example
    #   require "google/cloud"
    #
    #   gcloud  = Google::Cloud.new
    #   storage = gcloud.storage
    #   bucket = storage.bucket "my-bucket"
    #   file = bucket.file "path/to/my-file.ext"
    #
    # @example The default scope can be overridden with the `scope` option:
    #   require "google/cloud"
    #
    #   gcloud  = Google::Cloud.new
    #   readonly_scope = "https://www.googleapis.com/auth/devstorage.read_only"
    #   readonly_storage = gcloud.storage scope: readonly_scope
    #
    def storage scope: nil, retries: nil, timeout: nil, open_timeout: nil, read_timeout: nil, send_timeout: nil
      Google::Cloud.storage @project, @keyfile, scope: scope,
                                                retries: (retries || @retries),
                                                timeout: (timeout || @timeout),
                                                open_timeout: (open_timeout || timeout),
                                                read_timeout: (read_timeout || timeout),
                                                send_timeout: (send_timeout || timeout)
    end

    ##
    # Creates a new object for connecting to the Storage service.
    # Each call creates a new connection.
    #
    # For more information on connecting to Google Cloud see the
    # {file:AUTHENTICATION.md Authentication Guide}.
    #
    # @param [String] project_id Project identifier for the Storage service
    #   you are connecting to. If not present, the default project for the
    #   credentials is used.
    # @param [String, Hash, Google::Auth::Credentials] credentials The path to
    #   the keyfile as a String, the contents of the keyfile as a Hash, or a
    #   Google::Auth::Credentials object. (See {Storage::Credentials})
    # @param [String, Array<String>] scope The OAuth 2.0 scopes controlling the
    #   set of resources and operations that the connection can access. See
    #   [Using OAuth 2.0 to Access Google
    #   APIs](https://developers.google.com/identity/protocols/OAuth2).
    #
    #   The default scope is:
    #
    #   * `https://www.googleapis.com/auth/devstorage.full_control`
    # @param [Integer] retries Number of times to retry requests on server
    #   error. The default value is `3`. Optional.
    # @param [Integer] timeout (default timeout) The max duration, in seconds, to wait before timing out. Optional.
    #    If left blank, the wait will be at most the time permitted by the underlying HTTP/RPC protocol.
    # @param [Integer] open_timeout How long, in seconds, before failed connections time out. Optional.
    # @param [Integer] read_timeout How long, in seconds, before requests time out. Optional.
    # @param [Integer] send_timeout How long, in seconds, before receiving response from server times out. Optional.
    #
    # @return [Google::Cloud::Storage::Project]
    #
    # @example
    #   require "google/cloud/storage"
    #
    #   storage = Google::Cloud.storage "my-project",
    #                            "/path/to/keyfile.json"
    #
    #   bucket = storage.bucket "my-bucket"
    #   file = bucket.file "path/to/my-file.ext"
    #
    def self.storage project_id = nil, credentials = nil, scope: nil,
                     retries: nil, timeout: nil, open_timeout: nil, read_timeout: nil, send_timeout: nil
      require "google/cloud/storage"
      Google::Cloud::Storage.new project_id: project_id,
                                 credentials: credentials,
                                 scope: scope,
                                 retries: retries,
                                 timeout: timeout,
                                 open_timeout: (open_timeout || timeout),
                                 read_timeout: (read_timeout || timeout),
                                 send_timeout: (send_timeout || timeout)
    end
  end
end

# Set the default storage configuration
Google::Cloud.configure.add_config! :storage do |config|
  default_project = Google::Cloud::Config.deferred do
    ENV["STORAGE_PROJECT"]
  end
  default_creds = Google::Cloud::Config.deferred do
    Google::Cloud::Config.credentials_from_env(
      "STORAGE_CREDENTIALS", "STORAGE_CREDENTIALS_JSON",
      "STORAGE_KEYFILE", "STORAGE_KEYFILE_JSON"
    )
  end

  config.add_field! :project_id, default_project, match: String, allow_nil: true
  config.add_alias! :project, :project_id
  config.add_field! :credentials, default_creds,
                    match: [String, Hash, Google::Auth::Credentials],
                    allow_nil: true
  config.add_alias! :keyfile, :credentials
  config.add_field! :scope, nil, match: [String, Array]
  config.add_field! :quota_project, nil, match: String
  config.add_field! :retries, nil, match: Integer
  config.add_field! :timeout, nil, match: Integer
  config.add_field! :open_timeout, nil, match: Integer
  config.add_field! :read_timeout, nil, match: Integer
  config.add_field! :send_timeout, nil, match: Integer
  # TODO: Remove once discovery document is updated.
  config.add_field! :endpoint, "https://storage.googleapis.com/", match: String
end
