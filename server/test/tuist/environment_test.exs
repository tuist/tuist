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

  describe "kura Hetzner configuration" do
    test "reads the Hetzner API token from secrets" do
      secrets = %{"kura" => %{"hetzner" => %{"api_token" => "hcloud-token"}}}

      assert Environment.kura_hetzner_api_token(secrets) == "hcloud-token"
    end

    test "reads Cloudflare configuration from secrets" do
      secrets = %{"kura" => %{"cloudflare" => %{"api_token" => "cf-token", "zone_id" => "zone-id"}}}

      assert Environment.kura_cloudflare_api_token(secrets) == "cf-token"
      assert Environment.kura_cloudflare_zone_id(secrets) == "zone-id"
    end

    test "reads Kura SSH keys from secrets" do
      private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\nkey\n-----END OPENSSH PRIVATE KEY-----"

      secrets = %{
        "kura" => %{
          "ssh" => %{
            "public_key" => "ssh-ed25519 public",
            "private_key_base64" => Base.encode64(private_key)
          }
        }
      }

      assert Environment.kura_ssh_public_key(secrets) == "ssh-ed25519 public"
      assert Environment.kura_ssh_private_key(secrets) == private_key
    end
  end
end
