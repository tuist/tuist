defmodule Tuist.CacheEndpoints do
  @moduledoc """
  Context for managing global Tuist-hosted cache endpoints.
  """

  import Ecto.Query

  alias Tuist.CacheEndpoints.CacheEndpoint
  alias Tuist.Repo

  @doc "Lists all cache endpoints for a given environment, ordered by display_name."
  def list_cache_endpoints(environment) do
    CacheEndpoint
    |> where(environment: ^environment)
    |> order_by(:display_name)
    |> Repo.all()
  end

  @doc "Lists active (non-maintenance) cache endpoints for a given environment."
  def list_active_cache_endpoints(environment) do
    CacheEndpoint
    |> where(environment: ^environment)
    |> where([c], c.maintenance == false)
    |> order_by(:display_name)
    |> Repo.all()
  end

  @doc "Gets a single cache endpoint by ID. Raises if not found."
  def get_cache_endpoint!(id), do: Repo.get!(CacheEndpoint, id)

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

  @doc "Toggles the maintenance flag on a cache endpoint."
  def toggle_maintenance(%CacheEndpoint{} = endpoint) do
    endpoint
    |> CacheEndpoint.changeset(%{maintenance: !endpoint.maintenance})
    |> Repo.update()
  end
end
