# frozen_string_literal: true

require "test_helper"
require "octokit"

module Fourier
  module Utilities
    class GitHubClientTest < TestCase
      def test_the_right_access_token_is_passed
        # Given
        environment = { "GITHUB_TOKEN" => "token" }
        github_client = Utilities::GitHubClient.new(environment: environment)

        # Then
        assert_equal("token", github_client.access_token)
      end

      def test_auto_paginate_is_enabled
        # Given
        environment = { "GITHUB_TOKEN" => "token" }
        github_client = Utilities::GitHubClient.new(environment: environment)

        # Then
        assert(github_client.auto_paginate)
      end

      def test_raises_when_token_is_not_present_in_the_environment
        # Given
        environment = {}

        # Then
        assert_raises(Fourier::Utilities::GitHubClient::TokenNotFound) do
          Utilities::GitHubClient.new(environment: environment)
        end
      end
    end
  end
end
