# frozen_string_literal: true

require "test_helper"

class EnvironmentTest < ActiveSupport::TestCase
  def test_fetch_defaults_to_env_variables
    # Given
    env = { "TUIST_FOO" => "bar"}

    # When
    got = Environment.fetch(:foo, env: env)

    # Then
    assert_equal "bar", got
  end

  def test_fetch_fallsback_to_secrets_when_env_variable_is_absent
    # Given
    secrets = { foo: "bar" }

    # When
    got = Environment.fetch(:foo, credentials: secrets)

    # Then
    assert_equal "bar", got
  end

  def test_fetch_fallsback_to_defaults_when_env_variable_and_secrets_are_absent
    # Given
    defaults = { foo: "bar" }

    # When
    got = Environment.fetch(:foo, defaults: defaults)

    # Then
    assert_equal "bar", got
  end

  def test_fetch_with_bang_raises_when_variable_is_missing
    # Given
    env = {}

    # When
    assert_raises(Environment::KeyNotFoundError) do
      Environment.fetch!(:foo, env: env)
    end
  end
end
