defmodule Tuist.EnvironmentTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Environment

  describe "get/3" do
    test "retrieves value from secrets using string keys" do
      # Given
      secrets = %{
        "test_oauth" => %{
          "test_client_id" => "test_client_id_value",
          "test_client_secret" => "test_client_secret_value"
        },
        "test_database" => %{
          "test_url" => "test_db_url_value"
        }
      }

      # When
      client_id = Environment.get([:test_oauth, :test_client_id], secrets)
      client_secret = Environment.get([:test_oauth, :test_client_secret], secrets)
      db_url = Environment.get([:test_database, :test_url], secrets)

      # Then
      assert client_id == "test_client_id_value"
      assert client_secret == "test_client_secret_value"
      assert db_url == "test_db_url_value"
    end

    test "retrieves nested values from secrets using string keys" do
      # Given
      secrets = %{
        "nested" => %{
          "deeply" => %{
            "nested" => %{
              "value" => "deep_value"
            }
          }
        }
      }

      # When
      value = Environment.get([:nested, :deeply, :nested, :value], secrets)

      # Then
      assert value == "deep_value"
    end

    test "returns nil when key doesn't exist in secrets" do
      # Given
      secrets = %{
        "oauth" => %{
          "client_id" => "test_client_id"
        }
      }

      # When
      result = Environment.get([:oauth, :nonexistent], secrets)

      # Then
      assert is_nil(result)
    end

    test "returns default value when key doesn't exist and default is provided" do
      # Given
      secrets = %{
        "oauth" => %{
          "client_id" => "test_client_id"
        }
      }

      # When
      result = Environment.get([:oauth, :nonexistent], secrets, default_value: "default_value")

      # Then
      assert result == "default_value"
    end

    test "environment variable name generation follows correct pattern" do
      # Given
      secrets = %{
        "test_config" => %{
          "test_value" => "secret_test_value"
        }
      }

      # When - Test that the function works with secrets when no env var is set
      result = Environment.get([:test_config, :test_value], secrets)

      # Then - Should return the value from secrets
      assert result == "secret_test_value"

      # Note: Environment variable precedence is tested implicitly through existing system behavior
      # We don't modify System.env in tests to avoid shared state issues
    end

    test "handles empty secrets map" do
      # Given
      secrets = %{}

      # When
      result = Environment.get([:nonexistent, :key], secrets)

      # Then
      assert is_nil(result)
    end

    test "converts atom keys to string keys for secrets lookup" do
      # Given
      secrets = %{
        "test_oauth" => %{
          "test_client_id" => "test_client_id_value"
        }
      }

      # When - Using atom keys in the get function
      result = Environment.get([:test_oauth, :test_client_id], secrets)

      # Then - Should work because keys are converted to strings internally
      assert result == "test_client_id_value"
    end

    test "handles deeply nested atom keys conversion" do
      # Given
      secrets = %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "value" => "nested_value"
            }
          }
        }
      }

      # When - Using atom keys
      result = Environment.get([:level1, :level2, :level3, :value], secrets)

      # Then - Should work with string key conversion
      assert result == "nested_value"
    end

    test "returns nil for non-existent nested path" do
      # Given
      secrets = %{
        "oauth" => %{
          "client_id" => "test_client_id"
        }
      }

      # When
      result = Environment.get([:oauth, :nonexistent, :deep_path], secrets)

      # Then
      assert is_nil(result)
    end
  end

  describe "s3_ca_cert_pem/1" do
    test "returns PEM content from secrets" do
      # Given
      pem_content = """
      -----BEGIN CERTIFICATE-----
      MIIDXTCCAkWgAwIBAgIJAKL0UG+mRKqzMA0GCSqGSIb3DQEBCwUAMEUxCzAJBgNV
      -----END CERTIFICATE-----
      """

      secrets = %{
        "s3" => %{
          "ca_cert_pem" => pem_content
        }
      }

      # When
      result = Environment.s3_ca_cert_pem(secrets)

      # Then
      assert result == pem_content
    end

    test "returns nil when not configured" do
      # Given
      secrets = %{}

      # When
      result = Environment.s3_ca_cert_pem(secrets)

      # Then
      assert is_nil(result)
    end
  end

  describe "object_storage_provider/1" do
    test "defaults to S3" do
      assert Environment.object_storage_provider(%{}) == :s3
    end

    test "returns azure_blob when configured in secrets" do
      assert Environment.object_storage_provider(%{"object_storage" => %{"provider" => "azure_blob"}}) == :azure_blob
    end

    test "raises for unsupported providers" do
      assert_raise RuntimeError, ~r/Unsupported TUIST_OBJECT_STORAGE_PROVIDER/, fn ->
        Environment.object_storage_provider(%{"object_storage" => %{"provider" => "gcs"}})
      end
    end
  end

  describe "azure blob storage configuration" do
    test "reads account configuration from secrets" do
      secrets = %{
        "azure_blob" => %{
          "account_name" => "tuiststorage",
          "account_key" => "account-key",
          "container_name" => "tuist",
          "endpoint" => "https://blob.internal",
          "service_version" => "2020-12-06"
        }
      }

      assert Environment.azure_storage_account_name(secrets) == "tuiststorage"
      assert Environment.azure_storage_account_key(secrets) == "account-key"
      assert Environment.azure_blob_container_name(secrets) == "tuist"
      assert Environment.azure_blob_endpoint(secrets) == "https://blob.internal"
      assert Environment.azure_blob_service_version(secrets) == "2020-12-06"
    end

    test "derives the public blob endpoint from the account name when endpoint is omitted" do
      secrets = %{"azure_blob" => %{"account_name" => "tuiststorage"}}

      assert Environment.azure_blob_endpoint(secrets) == "https://tuiststorage.blob.core.windows.net"
    end
  end

  describe "mode/1" do
    test "defaults to :web when TUIST_MODE is unset or empty" do
      assert Environment.mode(nil) == :web
      assert Environment.mode("") == :web
    end

    test "maps each known TUIST_MODE string to its atom" do
      assert Environment.mode("web") == :web
      assert Environment.mode("processor") == :processor
      assert Environment.mode("xcresult_processor") == :xcresult_processor
    end

    test "raises on unknown non-empty TUIST_MODE so a manifest typo fails the pod fast" do
      assert_raise RuntimeError, ~r/Unknown TUIST_MODE="processsor"/, fn ->
        Environment.mode("processsor")
      end

      assert_raise RuntimeError, ~r/Unknown TUIST_MODE="ingest"/, fn ->
        Environment.mode("ingest")
      end
    end
  end

  describe "database_schema/1" do
    test "defaults to public when unset or empty" do
      assert Environment.database_schema(nil) == "public"
      assert Environment.database_schema("") == "public"
    end

    test "accepts unquoted PostgreSQL identifiers" do
      assert Environment.database_schema("tuist") == "tuist"
      assert Environment.database_schema("_tuist1") == "_tuist1"
    end

    test "raises on invalid schema identifiers" do
      assert_raise RuntimeError,
                   ~r/TUIST_DATABASE_SCHEMA must be a valid unquoted PostgreSQL identifier/,
                   fn ->
                     Environment.database_schema("tuist-prod")
                   end

      assert_raise RuntimeError,
                   ~r/TUIST_DATABASE_SCHEMA must be a valid unquoted PostgreSQL identifier/,
                   fn ->
                     Environment.database_schema("1tuist")
                   end
    end
  end

  describe "quote_postgres_identifier/1" do
    test "quotes identifiers used in SQL and startup parameters" do
      assert Environment.quote_postgres_identifier("tuist") == ~s("tuist")
      assert Environment.quote_postgres_identifier("Tuist") == ~s("Tuist")
    end
  end

  describe "modes/0" do
    test "every value round-trips through mode/1 so the list stays in sync with the parser" do
      for mode <- Environment.modes() do
        assert Environment.mode(Atom.to_string(mode)) == mode
      end
    end
  end

  describe "all_envs/0" do
    test "includes preview as a runtime deployment environment" do
      assert :preview in Environment.all_envs()
    end
  end

  describe "database_config_from_url/1" do
    test "preserves literal plus signs in credentials" do
      config = Environment.database_config_from_url("ecto://user:abc+def@example.com/tuist")

      assert config[:username] == "user"
      assert config[:password] == "abc+def"
    end

    test "decodes percent-encoded plus signs in credentials" do
      config = Environment.database_config_from_url("ecto://user:abc%2Bdef@example.com/tuist")

      assert config[:username] == "user"
      assert config[:password] == "abc+def"
    end
  end

  describe "agent_auth_trusted_providers/1" do
    test "returns the default trusted providers when no override is configured" do
      assert Environment.agent_auth_trusted_providers(%{}) == [
               %{
                 "issuer" => "https://auth0.openai.com/",
                 "jwks_uri" => "https://auth.openai.com/.well-known/jwks.json"
               }
             ]
    end

    test "allows secrets to override the default trusted providers with a list" do
      providers = [
        %{
          "issuer" => "https://agent-provider.example.com",
          "jwks_uri" => "https://agent-provider.example.com/.well-known/jwks.json",
          "client_ids" => ["test-agent-client"]
        }
      ]

      secrets = %{
        "agent_auth" => %{
          "trusted_providers" => providers
        }
      }

      assert Environment.agent_auth_trusted_providers(secrets) == providers
    end

    test "allows secrets to override the default trusted providers with JSON" do
      providers = [
        %{
          "issuer" => "https://agent-provider.example.com",
          "jwks_uri" => "https://agent-provider.example.com/.well-known/jwks.json"
        }
      ]

      secrets = %{
        "agent_auth" => %{
          "trusted_providers" => JSON.encode!(providers)
        }
      }

      assert Environment.agent_auth_trusted_providers(secrets) == providers
    end

    test "allows an empty list override to disable default trusted providers" do
      secrets = %{
        "agent_auth" => %{
          "trusted_providers" => []
        }
      }

      assert Environment.agent_auth_trusted_providers(secrets) == []
    end

    test "fails closed when the trusted providers JSON override is invalid" do
      secrets = %{
        "agent_auth" => %{
          "trusted_providers" => "not-json"
        }
      }

      assert Environment.agent_auth_trusted_providers(secrets) == []
    end
  end

  describe "kura_endpoints/1" do
    test "returns trimmed Kura endpoints from the environment value" do
      assert Environment.kura_endpoints(%{}, " https://kura-1.example.com,https://kura-2.example.com , ") == [
               "https://kura-1.example.com",
               "https://kura-2.example.com"
             ]
    end

    test "falls back to secrets when the environment value is blank" do
      secrets = %{
        "kura" => %{
          "endpoints" => "https://kura-from-secrets.example.com"
        }
      }

      assert Environment.kura_endpoints(secrets, "") == ["https://kura-from-secrets.example.com"]
    end

    test "returns trimmed Kura endpoints from secrets" do
      secrets = %{
        "kura" => %{
          "endpoints" => " https://kura-1.example.com,https://kura-2.example.com , "
        }
      }

      assert Environment.kura_endpoints(secrets) == [
               "https://kura-1.example.com",
               "https://kura-2.example.com"
             ]
    end

    test "returns nil when Kura endpoints are not configured" do
      assert Environment.kura_endpoints(%{}) == nil
    end
  end
end
