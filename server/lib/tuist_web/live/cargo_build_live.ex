defmodule TuistWeb.CargoBuildLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.CargoCacheInspection
  import TuistWeb.Components.EmptyTabStateBackground
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Cargo
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.Repo
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.CargoCache
  alias TuistWeb.Utilities.Query

  @compilation_limit 500
  @page_size 20

  def mount(%{"build_id" => id}, _session, %{assigns: %{selected_project: project}} = socket) do
    case Cargo.get_build(id, project.id) do
      {:ok, build} ->
        {:ok,
         socket
         |> assign(:head_title, "Cargo build · Tuist")
         |> assign(:build, Repo.preload(build, :ran_by_account))
         |> assign(:cache_metrics, CacheMetrics.read(build))
         |> assign_async(:compilations, fn ->
           rows = Cargo.compilations(build, @compilation_limit + 1)
           truncated = length(rows) > @compilation_limit

           rows =
             rows
             |> Enum.take(@compilation_limit)
             |> Enum.map(fn row -> %{row | diagnostics: JSON.decode!(row.diagnostics)} end)

           {:ok, %{compilations: %{rows: rows, truncated: truncated}}}
         end)}

      {:error, :not_found} ->
        raise TuistWeb.Errors.NotFoundError, "Cargo build not found"
    end
  end

  def handle_params(params, uri, socket) do
    tabs = if socket.assigns.cache_metrics, do: ["warnings", "errors", "cache"], else: ["warnings", "errors"]
    tab = if params["tab"] in tabs, do: params["tab"], else: "overview"
    sort = if params["compilations-sort-by"] in ["duration", "name"], do: params["compilations-sort-by"], else: "start"
    search = params |> Map.get("compilations-search", "") |> String.slice(0, 4096)
    cache_tab = if params["cache-tab"] == "cas-outputs", do: "cas-outputs", else: "cacheable-tasks"
    prefix = CargoCache.prefix(cache_tab)

    cache_sort =
      if params["#{prefix}-sort"] in CargoCache.sorts(cache_tab),
        do: params["#{prefix}-sort"],
        else: hd(CargoCache.sorts(cache_tab))

    requested_status = CargoCache.result(params["#{prefix}-status"])
    cache_status = if requested_status in CargoCache.statuses(cache_tab), do: requested_status, else: "all"

    {:noreply,
     assign(socket,
       uri: URI.parse(uri),
       selected_tab: tab,
       compilation_search: search,
       compilation_sort: sort,
       compilation_page: positive_integer(params["compilations-page"]),
       selected_cache_tab: cache_tab,
       cache_search: String.slice(params["#{prefix}-search"] || "", 0, 4096),
       cache_sort: cache_sort,
       cache_status: cache_status,
       cache_page: positive_integer(params["#{prefix}-page"], 250),
       cache_read_type: percentile_type(params["cache-read-type"]),
       cache_write_type: percentile_type(params["cache-write-type"])
     )}
  end

  def handle_event("search-compilations", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("compilations-search", search) |> Query.put("compilations-page", "1")
    {:noreply, push_patch(socket, to: "#{socket.assigns.uri.path}?#{query}", replace: true)}
  end

  def handle_event("search-cargo-cache", %{"search" => search}, socket) do
    query =
      CargoCache.patch(socket.assigns.uri, socket.assigns.selected_cache_tab, "search", String.slice(search, 0, 4096))

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri.path}#{query}", replace: true)}
  end

  def handle_event(event, %{"type" => type}, socket)
      when event in ["select-cargo-cache-read-type", "select-cargo-cache-write-type"] do
    key = if event == "select-cargo-cache-read-type", do: "cache-read-type", else: "cache-write-type"
    query = Query.put(socket.assigns.uri.query, key, percentile_type(type))
    {:noreply, push_patch(socket, to: "#{socket.assigns.uri.path}?#{query}", replace: true)}
  end

  defp percentile_type(type) when type in ~w(avg p99 p90 p50), do: type
  defp percentile_type(_), do: "avg"

  defp compilation_page(rows, search, sort, page) do
    search = String.downcase(search)
    rows = Enum.filter(rows, &String.contains?(String.downcase("#{&1.name} #{&1.source}"), search))

    rows =
      case sort do
        "duration" -> Enum.sort_by(rows, &{-&1.duration_ms, &1.id})
        "name" -> Enum.sort_by(rows, &{&1.name, &1.id})
        _ -> rows
      end

    pages = max(ceil(length(rows) / @page_size), 1)
    page = min(page, pages)
    %{rows: Enum.slice(rows, (page - 1) * @page_size, @page_size), page: page, pages: pages}
  end

  defp positive_integer(value, maximum \\ 25)

  defp positive_integer(value, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> min(number, maximum)
      _ -> 1
    end
  end

  defp positive_integer(_, _), do: 1
  defp available(""), do: dgettext("dashboard_builds", "Unknown")
  defp available(nil), do: dgettext("dashboard_builds", "Unknown")
  defp available(value), do: value
  defp sort_label("duration"), do: dgettext("dashboard_builds", "Duration")
  defp sort_label("name"), do: dgettext("dashboard_builds", "Name")
  defp sort_label(_), do: dgettext("dashboard_builds", "Started after")

  defp diagnostics(rows, severity) do
    rows
    |> Enum.flat_map(fn row ->
      row.diagnostics
      |> Enum.filter(&(&1["severity"] == severity))
      |> Enum.map(&Map.merge(&1, %{"crate" => row.name, "file" => &1["file"] || row.source}))
    end)
    |> Enum.group_by(& &1["file"])
    |> Enum.sort_by(fn {path, issues} -> {-length(issues), path} end)
  end

  attr :path, :string, required: true
  attr :issues, :list, required: true
  attr :severity, :string, required: true

  defp diagnostic_card(assigns) do
    ~H"""
    <div
      id={"cargo-#{@severity}-#{Base.url_encode64(:crypto.hash(:sha256, @path), padding: false)}"}
      phx-hook="NooraCollapsible"
      data-part="collapsible"
      data-state="closed"
      data-type={@severity}
      class="issue-card"
    >
      <div data-part="root">
        <div data-part="trigger">
          <div data-part="header">
            <div data-part="icon">
              <.alert_circle :if={@severity == "error"} />
              <.alert_hexagon :if={@severity == "warning"} />
            </div>
            <div data-part="title-and-subtitle">
              <h3 data-part="title">{available(@path)}</h3>
              <span data-part="subtitle">{@issues
              |> Enum.map(& &1["crate"])
              |> Enum.uniq()
              |> Enum.join(" • ")}</span>
            </div>
            <.badge
              label={format_number(length(@issues))}
              color={if @severity == "error", do: "destructive", else: "warning"}
              style="light-fill"
              size="large"
            />
          </div>
          <.neutral_button data-part="closed-collapsible-button" variant="secondary" size="medium">
            <.chevron_down />
          </.neutral_button>
          <.neutral_button data-part="open-collapsible-button" variant="secondary" size="medium">
            <.chevron_up />
          </.neutral_button>
        </div>
        <div data-part="content" data-state="closed">
          <span :for={issue <- @issues} data-part="issue">
            {issue["message"]}
            <span :if={issue["line"]}>{"#{@path}:#{issue["line"]}"}</span>
          </span>
        </div>
      </div>
    </div>
    """
  end
end
