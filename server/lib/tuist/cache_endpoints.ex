defmodule Tuist.CacheEndpoints do
  @moduledoc """
  Context for managing global Tuist-hosted cache endpoints.
  """

  import Ecto.Query

  alias Tuist.CacheEndpoints.CacheEndpoint
  alias Tuist.Repo

  @doc "Lists all cache endpoints for a given environment, ordered by display_name."
  def list_cache_endpoints(environment) do
    env = to_string(environment)

    CacheEndpoint
    |> where(environment: ^env)
    |> order_by(:display_name)
    |> Repo.all()
  end

  @doc "Lists active (non-maintenance) cache endpoints for a given environment."
  def list_active_cache_endpoints(environment) do
    env = to_string(environment)

    CacheEndpoint
    |> where(environment: ^env)
    |> where([c], c.maintenance == false)
    |> order_by(:display_name)
    |> Repo.all()
  end

  @doc "Gets a single cache endpoint by ID."
  def get_cache_endpoint(id) do
    case Repo.get(CacheEndpoint, id) do
      nil -> {:error, :not_found}
      endpoint -> {:ok, endpoint}
    end
  end

  @doc "Gets a single cache endpoint by URL and environment."
  def get_cache_endpoint_by_url(url, environment) do
    env = to_string(environment)

    CacheEndpoint
    |> where(url: ^url, environment: ^env)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      endpoint -> {:ok, endpoint}
    end
  end

  @doc "Creates a cache endpoint."
  def create_cache_endpoint(attrs) do
    attrs
    |> CacheEndpoint.changeset()
    |> Repo.insert()
  end

  @doc "Deletes a cache endpoint."
  def delete_cache_endpoint(%CacheEndpoint{} = endpoint) do
    Repo.delete(endpoint)
  end

  @doc "Returns active cache endpoint URLs. Uses secrets override if set, otherwise queries the database."
  def active_endpoint_urls do
    case Tuist.Environment.cache_endpoints() do
      endpoints when is_list(endpoints) ->
        endpoints

      nil ->
        if Tuist.Environment.tuist_hosted?() do
          Tuist.Environment.env()
          |> list_active_cache_endpoints()
          |> Enum.map(& &1.url)
        else
          []
        end
    end
  end

  @doc "Toggles the maintenance flag on a cache endpoint."
  def toggle_maintenance(%CacheEndpoint{} = endpoint) do
    endpoint
    |> CacheEndpoint.changeset(%{maintenance: !endpoint.maintenance})
    |> Repo.update()
  end
end
