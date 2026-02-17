defmodule Tuist.CacheEndpointsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.CacheEndpoints
  alias Tuist.CacheEndpoints.CacheEndpoint
  alias Tuist.Repo

  setup do
    Repo.delete_all(CacheEndpoint)
    :ok
  end

  defp create_endpoint(attrs \\ %{}) do
    default_attrs = %{
      url: "https://cache-test-#{System.unique_integer([:positive])}.tuist.dev",
      display_name: "Test Node"
    }

    {:ok, endpoint} = CacheEndpoints.create_cache_endpoint(Map.merge(default_attrs, attrs))
    endpoint
  end

  describe "list_cache_endpoints/0" do
    test "returns all endpoints ordered by display_name" do
      endpoint1 = create_endpoint(%{display_name: "Zebra"})
      endpoint2 = create_endpoint(%{display_name: "Alpha"})
      endpoint3 = create_endpoint(%{display_name: "Beta"})

      result = CacheEndpoints.list_cache_endpoints()

      assert length(result) == 3
      assert Enum.map(result, & &1.id) == [endpoint2.id, endpoint3.id, endpoint1.id]
    end

    test "returns empty list when no endpoints exist" do
      result = CacheEndpoints.list_cache_endpoints()

      assert result == []
    end
  end

  describe "list_active_cache_endpoints/0" do
    test "excludes disabled endpoints" do
      endpoint1 = create_endpoint(%{enabled: true})
      create_endpoint(%{enabled: false})

      result = CacheEndpoints.list_active_cache_endpoints()

      assert length(result) == 1
      assert hd(result).id == endpoint1.id
    end

    test "returns enabled endpoints ordered by display_name" do
      create_endpoint(%{display_name: "Zebra", enabled: true})
      create_endpoint(%{display_name: "Alpha", enabled: true})
      create_endpoint(%{display_name: "Beta", enabled: false})

      result = CacheEndpoints.list_active_cache_endpoints()

      assert length(result) == 2
      assert Enum.map(result, & &1.display_name) == ["Alpha", "Zebra"]
    end
  end

  describe "get_cache_endpoint/1" do
    test "returns the endpoint" do
      endpoint = create_endpoint()

      assert {:ok, result} = CacheEndpoints.get_cache_endpoint(endpoint.id)
      assert result.id == endpoint.id
      assert result.url == endpoint.url
    end

    test "returns error for non-existent ID" do
      assert {:error, :not_found} = CacheEndpoints.get_cache_endpoint(Ecto.UUID.generate())
    end
  end

  describe "create_cache_endpoint/1" do
    test "creates with valid attributes" do
      attrs = %{
        url: "https://cache.example.com",
        display_name: "Example Cache"
      }

      {:ok, endpoint} = CacheEndpoints.create_cache_endpoint(attrs)

      assert endpoint.url == "https://cache.example.com"
      assert endpoint.display_name == "Example Cache"
      assert endpoint.enabled == true
    end

    test "fails with missing required fields" do
      {:error, changeset} = CacheEndpoints.create_cache_endpoint(%{})

      assert "can't be blank" in errors_on(changeset).url
      assert "can't be blank" in errors_on(changeset).display_name
    end

    test "fails with duplicate url" do
      create_endpoint(%{url: "https://duplicate.example.com"})

      {:error, changeset} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "https://duplicate.example.com",
          display_name: "Another"
        })

      assert "has already been taken" in errors_on(changeset).url
    end
  end

  describe "validate_url" do
    test "accepts valid HTTPS URL" do
      {:ok, endpoint} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "https://cache.example.com",
          display_name: "Test"
        })

      assert endpoint.url == "https://cache.example.com"
    end

    test "accepts valid HTTP URL" do
      {:ok, endpoint} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "http://localhost:8087",
          display_name: "Test"
        })

      assert endpoint.url == "http://localhost:8087"
    end

    test "rejects URL without scheme" do
      {:error, changeset} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "cache.example.com",
          display_name: "Test"
        })

      assert "must be a valid HTTP or HTTPS URL" in errors_on(changeset).url
    end

    test "rejects URL with unsupported scheme" do
      {:error, changeset} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "ftp://cache.example.com",
          display_name: "Test"
        })

      assert "must be a valid HTTP or HTTPS URL" in errors_on(changeset).url
    end

    test "rejects non-URL string" do
      {:error, changeset} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "not-a-url",
          display_name: "Test"
        })

      assert "must be a valid HTTP or HTTPS URL" in errors_on(changeset).url
    end

    test "rejects URL with empty host" do
      {:error, changeset} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "https://",
          display_name: "Test"
        })

      assert "must be a valid HTTP or HTTPS URL" in errors_on(changeset).url
    end
  end

  describe "delete_cache_endpoint/1" do
    test "deletes the endpoint" do
      endpoint = create_endpoint()

      {:ok, deleted} = CacheEndpoints.delete_cache_endpoint(endpoint)

      assert deleted.id == endpoint.id
      assert {:error, :not_found} = CacheEndpoints.get_cache_endpoint(endpoint.id)
    end
  end

  describe "toggle_enabled/1" do
    test "toggles from true to false" do
      endpoint = create_endpoint(%{enabled: true})

      {:ok, updated} = CacheEndpoints.toggle_enabled(endpoint)

      assert updated.enabled == false
      assert updated.id == endpoint.id
    end

    test "toggles from false to true" do
      endpoint = create_endpoint(%{enabled: false})

      {:ok, updated} = CacheEndpoints.toggle_enabled(endpoint)

      assert updated.enabled == true
      assert updated.id == endpoint.id
    end

    test "persists the change to database" do
      endpoint = create_endpoint(%{enabled: true})

      {:ok, _updated} = CacheEndpoints.toggle_enabled(endpoint)

      assert {:ok, reloaded} = CacheEndpoints.get_cache_endpoint(endpoint.id)
      assert reloaded.enabled == false
    end
  end
end
