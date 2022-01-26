# Copyright 2014 Google, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "multi_json"
require "googleauth/credentials_loader"

module Google
  module Auth
    # Representation of an application's identity for user authorization
    # flows.
    class ClientId
      INSTALLED_APP = "installed".freeze
      WEB_APP = "web".freeze
      CLIENT_ID = "client_id".freeze
      CLIENT_SECRET = "client_secret".freeze
      MISSING_TOP_LEVEL_ELEMENT_ERROR =
        "Expected top level property 'installed' or 'web' to be present.".freeze

      # Text identifier of the client ID
      # @return [String]
      attr_reader :id

      # Secret associated with the client ID
      # @return [String]
      attr_reader :secret

      class << self
        attr_accessor :default
      end

      # Initialize the Client ID
      #
      # @param [String] id
      #  Text identifier of the client ID
      # @param [String] secret
      #  Secret associated with the client ID
      # @note Direction instantion is discouraged to avoid embedding IDs
      #       & secrets in source. See {#from_file} to load from
      #       `client_secrets.json` files.
      def initialize id, secret
        CredentialsLoader.warn_if_cloud_sdk_credentials id
        raise "Client id can not be nil" if id.nil?
        raise "Client secret can not be nil" if secret.nil?
        @id = id
        @secret = secret
      end

      # Constructs a Client ID from a JSON file downloaded from the
      # Google Developers Console.
      #
      # @param [String, File] file
      #  Path of file to read from
      # @return [Google::Auth::ClientID]
      def self.from_file file
        raise "File can not be nil." if file.nil?
        File.open file.to_s do |f|
          json = f.read
          config = MultiJson.load json
          from_hash config
        end
      end

      # Constructs a Client ID from a previously loaded JSON file. The hash
      # structure should
      # match the expected JSON format.
      #
      # @param [hash] config
      #  Parsed contents of the JSON file
      # @return [Google::Auth::ClientID]
      def self.from_hash config
        raise "Hash can not be nil." if config.nil?
        raw_detail = config[INSTALLED_APP] || config[WEB_APP]
        raise MISSING_TOP_LEVEL_ELEMENT_ERROR if raw_detail.nil?
        ClientId.new raw_detail[CLIENT_ID], raw_detail[CLIENT_SECRET]
      end
    end
  end
end
