# frozen_string_literal: true

require "test_helper"

class EnvironmentTest < ActiveSupport::TestCase
  def test_use_env_secrets
    # Given
    values = Environment::TRUTHY_VALUES

    # When/Then
    values.each do |value|
      assert(Environment.use_env_variables?(env: { "TUIST_CLOUD_ENV_VARIABLES" => value }))
    end

    assert_not(Environment.use_env_variables?(env: { "TUIST_CLOUD_ENV_VARIABLES" => "0" }))
  end
end
