defmodule Tuist.CacheEndpoints do
  @moduledoc """
  Context for managing global Tuist-hosted cache endpoints.
  """

  import Ecto.Query

  alias Tuist.CacheEndpoints.CacheEndpoint
  alias Tuist.Repo

  @doc "Lists all cache endpoints ordered by display_name."
  def list_cache_endpoints do
    CacheEndpoint
    |> order_by(:display_name)
    |> Repo.all()
  end

  @doc "Lists enabled cache endpoints ordered by display_name."
  def list_active_cache_endpoints do
    CacheEndpoint
    |> where([c], c.enabled == true)
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

  @doc "Gets a single cache endpoint by URL."
  def get_cache_endpoint_by_url(url) do
    CacheEndpoint
    |> where(url: ^url)
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
          Enum.map(list_active_cache_endpoints(), & &1.url)
        else
          []
        end
    end
  end

  @doc "Toggles the enabled flag on a cache endpoint."
  def toggle_enabled(%CacheEndpoint{} = endpoint) do
    endpoint
    |> CacheEndpoint.changeset(%{enabled: !endpoint.enabled})
    |> Repo.update()
  end
end
