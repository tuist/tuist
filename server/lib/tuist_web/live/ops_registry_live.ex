defmodule TuistWeb.OpsRegistryLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Registry
  alias TuistWeb.Utilities.Pagination
  alias TuistWeb.Utilities.Query

  @page_size 30

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:head_title, "Registry · Tuist Ops")
     |> assign_async(:packages, fn ->
       case Registry.list_swift_packages() do
         {:ok, packages} -> {:ok, %{packages: packages}}
         {:error, reason} -> {:error, reason}
       end
     end)}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    query_params = Query.query_params(uri)

    {:noreply,
     socket
     |> assign(:query_params, query_params)
     |> assign(:search, query_params["search"] || "")
     |> assign(:page, Pagination.parse_page(query_params["page"]))}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params =
      socket.assigns.query_params
      |> Map.put("search", search)
      |> Map.delete("page")

    {:noreply, push_patch(socket, to: ~p"/ops/registry?#{params}")}
  end

  def filtered_packages(packages, search) do
    search = search |> String.trim() |> String.downcase()

    if search == "" do
      packages
    else
      Enum.filter(packages, fn package ->
        package.repository_full_handle
        |> String.downcase()
        |> String.contains?(search)
      end)
    end
  end

  def paginated_packages(packages, page), do: Pagination.paginate(packages, page, @page_size)

  def total_pages(packages), do: Pagination.total_pages(length(packages), @page_size)

  def current_page(page, total_pages), do: Pagination.current_page(page, total_pages)

  def page_path(query_params, page) do
    ~p"/ops/registry?#{Map.put(query_params, "page", page)}"
  end
end
