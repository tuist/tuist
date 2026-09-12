defmodule TuistWeb.OnceInvocationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Once
  alias Tuist.Once.Invocation
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @page_size 30

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    socket =
      socket
      |> assign(
        :head_title,
        "#{dgettext("dashboard_projects", "Once invocations")} · #{account.name}/#{project.name} · Tuist"
      )
      |> assign(OpenGraph.og_image_assigns("overview"))

    {:ok, load_invocations(socket)}
  end

  def handle_params(_params, uri, socket) do
    query_params = Query.query_params(uri)
    page = parse_page(query_params["page"])

    {:noreply,
     socket
     |> assign(:query_params, query_params)
     |> assign(:page, page)}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_invocations(socket)}
  end

  defp load_invocations(%{assigns: %{selected_project: project}} = socket) do
    invocations = Once.list_invocations(project.id, limit: 200)
    hit_ratio = Once.cache_hit_ratio(project.id)

    socket
    |> assign(:invocations, invocations)
    |> assign(:cache_hit_ratio, hit_ratio)
    |> assign(:total_invocations, length(invocations))
  end

  def paginated_invocations(invocations, page) do
    Enum.slice(invocations, (page - 1) * @page_size, @page_size)
  end

  def total_pages(invocations) do
    invocations
    |> length()
    |> Kernel./(@page_size)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  def current_page(page, total_pages), do: min(page, total_pages)

  def page_path(query_params, page) do
    "?" <> URI.encode_query(Map.put(query_params, "page", page))
  end

  def format_duration(nil), do: "-"
  def format_duration(ms) when is_integer(ms), do: DateFormatter.format_duration_from_milliseconds(ms)

  def format_datetime(nil), do: "-"

  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  def cache_badge_color("hit"), do: "success"
  def cache_badge_color("miss"), do: "warning"
  def cache_badge_color("bypass"), do: "neutral"
  def cache_badge_color(_), do: "neutral"

  def status_badge_color("success"), do: "success"
  def status_badge_color("failure"), do: "destructive"
  def status_badge_color(_), do: "neutral"

  def format_ratio_percent(ratio) when is_float(ratio) do
    "~.1f%" |> :io_lib.format([ratio * 100]) |> IO.iodata_to_binary()
  end

  def format_ratio_percent(_), do: "-"

  def invocation_command(%Invocation{command: command, argv: argv}) do
    argv_summary =
      argv
      |> Enum.take(6)
      |> Enum.join(" ")

    if argv_summary == "", do: command, else: "#{command} #{argv_summary}"
  end

  defp parse_page(nil), do: 1

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end
end
