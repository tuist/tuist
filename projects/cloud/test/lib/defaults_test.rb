# frozen_string_literal: true

require "test_helper"

class DefaultsTest < ActiveSupport::TestCase
  def test_fetch_when_env_secrets_and_key_exists
    # Given
    env = { "TUIST_GITHUB_TOKEN" => "token" }
    app_defaults = {}
    Environment.stubs(:use_env_variables?).returns(true)

    # When
    got = Defaults.fetch(:github, :token, env: env, app_defaults: app_defaults)

    # Then
    assert_equal("token", got)
  end

  def test_fetch_when_env_secrets_and_key_doesnt_exist
    # Given
    env = {}
    app_defaults = {}
    Environment.stubs(:use_env_variables?).returns(true)

    # When/Then
    assert_raises(KeyError) do
      Defaults.fetch(:github, :token, env: env, app_defaults: app_defaults)
    end
  end

  def test_fetch_when_not_env_secrets_and_key_exists
    # Given
    env = {}
    app_defaults = { github: { token: "token" } }
    Environment.stubs(:use_env_variables?).returns(false)

    # When
    got = Defaults.fetch(:github, :token, env: env, app_defaults: app_defaults)

    # Then
    assert_equal("token", got)
  end

  def test_fetch_when_not_env_secrets_and_key_doesnt_exist
    # Given
    env = {}
    app_defaults = {}
    Environment.stubs(:use_env_variables?).returns(false)

    # When/Then
    assert_raises(Defaults::KeyNotFoundError) do
      Defaults.fetch(:github, :token, env: env, app_defaults: app_defaults)
    end
  end
end
