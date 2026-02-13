defmodule TuistWeb.OpsCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.CacheEndpoints
  alias Tuist.Environment

  @impl true
  def mount(_params, _session, socket) do
    endpoints = CacheEndpoints.list_cache_endpoints(Environment.env())

    {:ok,
     socket
     |> assign(:endpoints, endpoints)
     |> assign(:head_title, "Cache Operations · Tuist")}
  end

  @impl true
  def handle_event("toggle_maintenance", %{"id" => id}, socket) do
    endpoint = CacheEndpoints.get_cache_endpoint!(id)
    {:ok, _endpoint} = CacheEndpoints.toggle_maintenance(endpoint)
    endpoints = CacheEndpoints.list_cache_endpoints(Environment.env())
    {:noreply, assign(socket, :endpoints, endpoints)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    endpoint = CacheEndpoints.get_cache_endpoint!(id)
    {:ok, _endpoint} = CacheEndpoints.delete_cache_endpoint(endpoint)
    endpoints = CacheEndpoints.list_cache_endpoints(Environment.env())
    {:noreply, assign(socket, :endpoints, endpoints)}
  end

  @impl true
  def handle_event("add", %{"url" => url, "display_name" => display_name}, socket) do
    case CacheEndpoints.create_cache_endpoint(%{
           url: url,
           display_name: display_name,
           environment: Environment.env()
         }) do
      {:ok, _endpoint} ->
        endpoints = CacheEndpoints.list_cache_endpoints(Environment.env())
        {:noreply, assign(socket, :endpoints, endpoints)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end
end
