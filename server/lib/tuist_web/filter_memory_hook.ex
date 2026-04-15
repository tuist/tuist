defmodule TuistWeb.FilterMemoryHook do
  @moduledoc """
  LiveView `on_mount` hook that loads the user's per-tab filter memory into
  `socket.assigns.last_queries` and attaches a `:handle_params` callback that
  writes the current list route's query string back into
  `Tuist.FilterMemory` on every live patch.

  The sidebar reads `@last_queries` to append stored query strings to its
  navigation links, restoring the user's filters when they return to a list
  page via the sidebar.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, get_connect_params: 1, push_event: 3]

  alias Tuist.FilterMemory

  # Maps project-relative path (after stripping /<account>/<project>) to the
  # key used in `last_queries`. Only list routes with filter UIs appear here.
  @routes %{
    "" => "overview",
    "/builds" => "builds",
    "/builds/build-runs" => "build-runs",
    "/tests" => "tests",
    "/tests/test-runs" => "test-runs",
    "/tests/test-cases" => "test-cases",
    "/tests/flaky-tests" => "flaky-tests",
    "/tests/quarantined-tests" => "quarantined-tests",
    "/tests/shards" => "shards",
    "/module-cache" => "module-cache",
    "/module-cache/cache-runs" => "cache-runs",
    "/module-cache/generate-runs" => "generate-runs",
    "/xcode-cache" => "xcode-cache",
    "/gradle-cache" => "gradle-cache",
    "/bundles" => "bundles",
    "/previews" => "previews"
  }

  def route_keys, do: Map.values(@routes)

  @doc """
  Appends the stored query string for `key` to `path` if one has been
  remembered, otherwise returns `path` unchanged. Intended for use in sidebar
  links and detail-page back buttons that target a list route.
  """
  def with_memory(path, last_queries, key) do
    case Map.get(last_queries, key) do
      query when is_binary(query) and query != "" -> path <> "?" <> query
      _ -> path
    end
  end

  def on_mount(:default, _params, _session, socket) do
    tab = read_tab_id(socket)
    last_queries = FilterMemory.get_all(user_id(socket), tab)

    socket =
      socket
      |> assign(:filter_memory_tab_id, tab)
      |> assign(:last_queries, last_queries)
      |> maybe_push_memory(last_queries)
      |> attach_hook(:filter_memory, :handle_params, &remember/3)

    {:cont, socket}
  end

  defp remember(_params, uri, socket) do
    with user_id when not is_nil(user_id) <- user_id(socket),
         tab when is_binary(tab) and tab != "" <- socket.assigns[:filter_memory_tab_id],
         %URI{path: path, query: query} <- URI.parse(uri),
         route_key when is_binary(route_key) <- route_key(path, socket) do
      query = query || ""
      :ok = FilterMemory.put(user_id, tab, route_key, query)
      queries = Map.put(socket.assigns.last_queries, route_key, query)

      {:cont,
       socket
       |> assign(:last_queries, queries)
       |> maybe_push_memory(queries)}
    else
      _ -> {:cont, socket}
    end
  end

  defp maybe_push_memory(socket, queries) do
    if Phoenix.LiveView.connected?(socket) do
      push_event(socket, "filter-memory", %{queries: queries})
    else
      socket
    end
  end

  defp user_id(socket) do
    case socket.assigns do
      %{current_user: %{id: id}} -> id
      _ -> nil
    end
  end

  defp read_tab_id(socket) do
    if Phoenix.LiveView.connected?(socket) do
      case get_connect_params(socket) do
        %{"tab_id" => id} when is_binary(id) and id != "" -> id
        _ -> nil
      end
    end
  end

  defp route_key(path, socket) when is_binary(path) do
    with %{selected_account: %{name: account}, selected_project: %{name: project}} <-
           socket.assigns,
         prefix = "/#{account}/#{project}",
         true <- String.starts_with?(path, prefix) do
      suffix = String.replace_prefix(path, prefix, "")
      Map.get(@routes, suffix)
    else
      _ -> nil
    end
  end

  defp route_key(_path, _socket), do: nil
end
