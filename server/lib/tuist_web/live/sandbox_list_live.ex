defmodule TuistWeb.SandboxListLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.SandboxesLive, only: [sandboxes_table: 1]

  alias Tuist.Sandboxes
  alias TuistWeb.SandboxesLive
  alias TuistWeb.Utilities.Query

  @refresh_interval 5_000
  @page_size 20
  @filters ["all", "running", "paused", "error"]

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    SandboxesLive.ensure_available!(user, account)

    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok, assign(socket, head_title: "#{dgettext("dashboard_sandboxes", "All sandboxes")} · #{account.name} · Tuist")}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply,
     socket
     |> assign(
       uri: URI.parse(uri),
       filter: if(params["status"] in @filters, do: params["status"], else: "all"),
       page: parse_page(params["page"])
     )
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load(socket)}
  end

  defp load(%{assigns: %{selected_account: account, filter: filter, page: page}} = socket) do
    counts = Sandboxes.count_sandboxes_by_state(account)
    total_pages = max(1, ceil(filter_count(counts, filter) / @page_size))
    page = min(page, total_pages)

    assign(socket,
      sandboxes:
        Sandboxes.list_sandboxes(account,
          states: filter_states(filter),
          limit: @page_size,
          offset: (page - 1) * @page_size
        ),
      counts: counts,
      page: page,
      total_pages: total_pages
    )
  end

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  @doc """
  The page's URL with `key` set to `value`. A new status starts again on
  the first page.
  """
  def list_patch(account, uri, "status", value) do
    query = uri.query |> Query.drop("page") |> Query.drop("status")
    list_path(account, if(value == "all", do: query, else: Query.put(query, "status", value)))
  end

  def list_patch(account, uri, key, value), do: list_path(account, Query.put(uri.query, key, value))

  defp list_path(account, ""), do: "/#{account.name}/sandboxes/all"
  defp list_path(account, query), do: "/#{account.name}/sandboxes/all?#{query}"

  defp filter_states("all"), do: nil
  defp filter_states("running"), do: [:creating, :resuming, :running]
  defp filter_states("paused"), do: [:paused, :archived]
  defp filter_states("error"), do: [:error]

  def filter_options do
    [
      {"all", dgettext("dashboard_sandboxes", "All")},
      {"running", dgettext("dashboard_sandboxes", "Running")},
      {"paused", dgettext("dashboard_sandboxes", "Paused")},
      {"error", dgettext("dashboard_sandboxes", "Failed")}
    ]
  end

  def filter_label(filter), do: filter_options() |> List.keyfind(filter, 0) |> elem(1)

  def filter_count(counts, "all"), do: counts |> Map.values() |> Enum.sum()

  def filter_count(counts, filter), do: filter |> filter_states() |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()
end
