# Copyright 2015 Google, Inc.
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

require "googleauth/signet"
require "googleauth/credentials_loader"
require "multi_json"

module Google
  module Auth
    # Small utility for normalizing scopes into canonical form
    module ScopeUtil
      ALIASES = {
        "email"   => "https://www.googleapis.com/auth/userinfo.email",
        "profile" => "https://www.googleapis.com/auth/userinfo.profile",
        "openid"  => "https://www.googleapis.com/auth/plus.me"
      }.freeze

      def self.normalize scope
        list = as_array scope
        list.map { |item| ALIASES[item] || item }
      end

      def self.as_array scope
        case scope
        when Array
          scope
        when String
          scope.split
        else
          raise "Invalid scope value. Must be string or array"
        end
      end
    end
  end
end
