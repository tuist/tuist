# frozen_string_literal: true

require "test_helper"

class SecretsTest < ActiveSupport::TestCase
  def test_fetch_when_env_secrets_and_key_exists
    # Given
    env = { "TUIST_GITHUB_TOKEN" => "token" }
    app_credentials = {}
    Environment.stubs(:use_env_variables?).returns(true)

    # When
    got = Secrets.fetch(:github, :token, env: env, app_credentials: app_credentials)

    # Then
    assert_equal("token", got)
  end

  def test_fetch_when_env_secrets_and_key_doesnt_exist
    # Given
    env = {}
    app_credentials = {}
    Environment.stubs(:use_env_variables?).returns(true)

    # When/Then
    assert_raises(KeyError) do
      Secrets.fetch(:github, :token, env: env, app_credentials: app_credentials)
    end
  end

  def test_fetch_when_not_env_secrets_and_key_exists
    # Given
    env = {}
    app_credentials = { github: { token: "token" } }
    Environment.stubs(:use_env_variables?).returns(false)

    # When
    got = Secrets.fetch(:github, :token, env: env, app_credentials: app_credentials)

    # Then
    assert_equal("token", got)
  end

  def test_fetch_when_not_env_secrets_and_key_doesnt_exist
    # Given
    env = {}
    app_credentials = {}
    Environment.stubs(:use_env_variables?).returns(false)

    # When/Then
    assert_raises(Secrets::KeyNotFoundError) do
      Secrets.fetch(:github, :token, env: env, app_credentials: app_credentials)
    end
  end
end
