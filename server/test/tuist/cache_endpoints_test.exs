defmodule Tuist.CacheEndpointsTest do
  use Tuist.DataCase, async: true

  alias Tuist.CacheEndpoints
  alias Tuist.CacheEndpoints.CacheEndpoint

  defp create_endpoint(attrs \\ %{}) do
    default_attrs = %{
      url: "https://cache-test-#{System.unique_integer([:positive])}.tuist.dev",
      display_name: "Test Node",
      environment: "test"
    }

    {:ok, endpoint} = CacheEndpoints.create_cache_endpoint(Map.merge(default_attrs, attrs))
    endpoint
  end

  describe "list_cache_endpoints/1" do
    test "returns endpoints for the given environment ordered by display_name" do
      endpoint1 = create_endpoint(%{display_name: "Zebra"})
      endpoint2 = create_endpoint(%{display_name: "Alpha"})
      endpoint3 = create_endpoint(%{display_name: "Beta"})

      result = CacheEndpoints.list_cache_endpoints("test")

      assert length(result) == 3
      assert Enum.map(result, & &1.id) == [endpoint2.id, endpoint3.id, endpoint1.id]
    end

    test "returns empty list for environment with no endpoints" do
      create_endpoint(%{environment: "prod"})

      result = CacheEndpoints.list_cache_endpoints("stag")

      assert result == []
    end

    test "filters by environment" do
      create_endpoint(%{environment: "prod"})
      create_endpoint(%{environment: "test"})

      result = CacheEndpoints.list_cache_endpoints("prod")

      assert length(result) == 1
      assert hd(result).environment == "prod"
    end
  end

  describe "list_active_cache_endpoints/1" do
    test "excludes maintenance endpoints" do
      endpoint1 = create_endpoint(%{maintenance: false})
      endpoint2 = create_endpoint(%{maintenance: true})

      result = CacheEndpoints.list_active_cache_endpoints("test")

      assert length(result) == 1
      assert hd(result).id == endpoint1.id
    end

    test "returns active endpoints ordered by display_name" do
      create_endpoint(%{display_name: "Zebra", maintenance: false})
      create_endpoint(%{display_name: "Alpha", maintenance: false})
      create_endpoint(%{display_name: "Beta", maintenance: true})

      result = CacheEndpoints.list_active_cache_endpoints("test")

      assert length(result) == 2
      assert Enum.map(result, & &1.display_name) == ["Alpha", "Zebra"]
    end

    test "filters by environment" do
      create_endpoint(%{environment: "prod", maintenance: false})
      create_endpoint(%{environment: "test", maintenance: false})

      result = CacheEndpoints.list_active_cache_endpoints("prod")

      assert length(result) == 1
      assert hd(result).environment == "prod"
    end
  end

  describe "get_cache_endpoint!/1" do
    test "returns the endpoint" do
      endpoint = create_endpoint()

      result = CacheEndpoints.get_cache_endpoint!(endpoint.id)

      assert result.id == endpoint.id
      assert result.url == endpoint.url
    end

    test "raises for non-existent ID" do
      assert_raise Ecto.NoResultsError, fn ->
        CacheEndpoints.get_cache_endpoint!("nonexistent-id")
      end
    end
  end

  describe "create_cache_endpoint/1" do
    test "creates with valid attributes" do
      attrs = %{
        url: "https://cache.example.com",
        display_name: "Example Cache",
        environment: "prod"
      }

      {:ok, endpoint} = CacheEndpoints.create_cache_endpoint(attrs)

      assert endpoint.url == "https://cache.example.com"
      assert endpoint.display_name == "Example Cache"
      assert endpoint.environment == "prod"
      assert endpoint.maintenance == false
    end

    test "fails with missing required fields" do
      {:error, changeset} = CacheEndpoints.create_cache_endpoint(%{})

      assert "can't be blank" in errors_on(changeset).url
      assert "can't be blank" in errors_on(changeset).display_name
      assert "can't be blank" in errors_on(changeset).environment
    end

    test "fails with invalid URL" do
      {:error, changeset} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "not-a-url",
          display_name: "Test",
          environment: "test"
        })

      assert "must be a valid HTTP or HTTPS URL" in errors_on(changeset).url
    end

    test "fails with invalid environment" do
      {:error, changeset} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "https://cache.example.com",
          display_name: "Test",
          environment: "invalid"
        })

      assert "is invalid" in errors_on(changeset).environment
    end

    test "fails with duplicate url + environment" do
      create_endpoint(%{
        url: "https://duplicate.example.com",
        environment: "prod"
      })

      {:error, changeset} =
        CacheEndpoints.create_cache_endpoint(%{
          url: "https://duplicate.example.com",
          display_name: "Another",
          environment: "prod"
        })

      assert "has already been taken" in errors_on(changeset).url
    end

    test "allows same URL in different environments" do
      url = "https://cache.example.com"

      {:ok, endpoint1} =
        CacheEndpoints.create_cache_endpoint(%{
          url: url,
          display_name: "Test 1",
          environment: "prod"
        })

      {:ok, endpoint2} =
        CacheEndpoints.create_cache_endpoint(%{
          url: url,
          display_name: "Test 2",
          environment: "stag"
        })

      assert endpoint1.url == endpoint2.url
      assert endpoint1.environment != endpoint2.environment
    end
  end

  describe "delete_cache_endpoint/1" do
    test "deletes the endpoint" do
      endpoint = create_endpoint()

      {:ok, deleted} = CacheEndpoints.delete_cache_endpoint(endpoint)

      assert deleted.id == endpoint.id

      assert_raise Ecto.NoResultsError, fn ->
        CacheEndpoints.get_cache_endpoint!(endpoint.id)
      end
    end
  end

  describe "toggle_maintenance/1" do
    test "toggles from false to true" do
      endpoint = create_endpoint(%{maintenance: false})

      {:ok, updated} = CacheEndpoints.toggle_maintenance(endpoint)

      assert updated.maintenance == true
      assert updated.id == endpoint.id
    end

    test "toggles from true to false" do
      endpoint = create_endpoint(%{maintenance: true})

      {:ok, updated} = CacheEndpoints.toggle_maintenance(endpoint)

      assert updated.maintenance == false
      assert updated.id == endpoint.id
    end

    test "persists the change to database" do
      endpoint = create_endpoint(%{maintenance: false})

      {:ok, _updated} = CacheEndpoints.toggle_maintenance(endpoint)

      reloaded = CacheEndpoints.get_cache_endpoint!(endpoint.id)
      assert reloaded.maintenance == true
    end
  end
end
