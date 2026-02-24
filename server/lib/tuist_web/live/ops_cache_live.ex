defmodule TuistWeb.OpsCacheLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.CacheEndpoints

  @impl true
  def mount(_params, _session, socket) do
    endpoints = CacheEndpoints.list_cache_endpoints()

    {:ok,
     socket
     |> assign(:endpoints, endpoints)
     |> assign(:head_title, "Cache Operations · Tuist")}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => id}, socket) do
    case CacheEndpoints.get_cache_endpoint(id) do
      {:ok, endpoint} ->
        {:ok, _endpoint} = CacheEndpoints.toggle_enabled(endpoint)
        endpoints = CacheEndpoints.list_cache_endpoints()
        {:noreply, assign(socket, :endpoints, endpoints)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case CacheEndpoints.get_cache_endpoint(id) do
      {:ok, endpoint} ->
        {:ok, _endpoint} = CacheEndpoints.delete_cache_endpoint(endpoint)
        endpoints = CacheEndpoints.list_cache_endpoints()
        {:noreply, assign(socket, :endpoints, endpoints)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add", %{"url" => url, "display_name" => display_name}, socket) do
    case CacheEndpoints.create_cache_endpoint(%{
           url: url,
           display_name: display_name
         }) do
      {:ok, _endpoint} ->
        endpoints = CacheEndpoints.list_cache_endpoints()
        {:noreply, assign(socket, :endpoints, endpoints)}

      {:error, changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
          |> Enum.map_join(", ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed to add endpoint: #{message}")}
    end
  end
end
