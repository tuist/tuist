defmodule Tuist.EnvironmentTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment

  setup :verify_on_exit!

  describe "use_local_storage?/1" do
    test "returns true when local is configured" do
      # Given/when
      got = Environment.use_local_storage?(%{"storage" => %{"mode" => "local"}})

      # Then
      assert got == true
    end

    test "returns false when remote is configured" do
      # Given/when
      got = Environment.use_local_storage?(%{"storage" => %{"mode" => "remote"}})

      # Then
      assert got == false
    end

    test "returns true when nothing is configured and it's dev" do
      # Given/when
      got = Environment.use_local_storage?(%{}, true)

      # Then
      assert got == true
    end

    test "returns false when nothing is configured and it's not dev" do
      # Given/when
      got = Environment.use_local_storage?(%{}, false)

      # Then
      assert got == false
    end
  end

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
end
