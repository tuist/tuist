defmodule TuistWeb.ReapiCacheOutputs do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.AsyncCard
  import TuistWeb.Components.Skeleton
  import TuistWeb.Widget

  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Utilities.Query

  def event_filters(invocation_id),
    do: [
      %{field: :invocation_id, op: :==, value: invocation_id},
      %{field: :operation, op: :==, value: "cas"},
      %{field: :outcome, op: :!=, value: "miss"}
    ]

  def params(invocation_id, params) do
    filters = event_filters(invocation_id)

    filters =
      if params["cache-output-key"] in [nil, ""],
        do: filters,
        else: filters ++ [%{field: :action_digest, op: :==, value: params["cache-output-key"]}]

    filters =
      if params["cache-output-search"] in [nil, ""],
        do: filters,
        else: filters ++ [%{field: :action_digest, op: :ilike, value: params["cache-output-search"]}]

    filters =
      if params["cache-output-operation"] in ~w(hit write),
        do: filters ++ [%{field: :outcome, op: :==, value: params["cache-output-operation"]}],
        else: filters

    page =
      case Integer.parse(params["cache-output-page"] || "1") do
        {page, ""} when page > 0 -> min(page, 10_000)
        _ -> 1
      end

    %{
      filters: filters,
      page: page,
      page_size: 20,
      order_by: [if(params["cache-output-sort-by"] == "key", do: :action_digest, else: :size)],
      order_directions: [if(params["cache-output-sort-order"] == "asc", do: :asc, else: :desc)]
    }
  end

  def output_link(query, digest),
    do:
      query
      |> Query.put("cache-tab", "cas-outputs")
      |> Query.put("cache-output-key", digest)
      |> Query.put("cache-output-page", "1")
      |> Query.drop("cache-output-search")
      |> Query.drop("cache-output-operation")

  attr :metrics, :any, required: true
  attr :outputs, :any, required: true
  attr :uri, :any, required: true
  attr :title, :string, required: true
  attr :artifact_type, :string, required: true
  attr :id, :string, required: true

  def card(assigns) do
    assigns = assign(assigns, :params, URI.decode_query(assigns.uri.query || ""))

    ~H"""
    <.async_card
      :let={ready?}
      results={[@metrics, @outputs]}
      title={@title}
      icon="database"
      data-part="mix-cache-card"
    >
      <.card_section data-part="mix-cache-card-section">
        <.card_section
          :if={
            ready? and
              @metrics.result.content_download_count + @metrics.result.content_upload_count > 0
          }
          data-part="cacheable-tasks-card-section"
        >
          <div data-part="title">
            <span data-part="label">{dgettext("dashboard_builds", "CAS outputs:")}</span><span data-part="value">{@metrics.result.content_download_count +
              @metrics.result.content_upload_count}</span>
          </div>
          <.chart
            id={@id <> "-chart"}
            type="bar"
            series={series(@metrics.result)}
            extra_options={chart_options()}
            x_axis_min={0}
            x_axis_max={@metrics.result.content_download_count + @metrics.result.content_upload_count}
          />
        </.card_section>
        <div data-part="throughput-widgets">
          <.widget
            :for={
              {operation, label} <- [
                {"download", dgettext("dashboard_builds", "Download throughput")},
                {"upload", dgettext("dashboard_builds", "Upload throughput")}
              ]
            }
            id={@id <> "-" <> operation <> "-throughput"}
            title={label}
            description={
              dgettext(
                "dashboard_builds",
                "Time-weighted CAS transfer throughput reported by Kura through the shared REAPI analytics pipeline, excluding action-cache metadata and local copies."
              )
            }
            loading={!ready?}
            value={
              if ready?,
                do: ThroughputFormatter.format_throughput(throughput(@metrics.result, operation))
            }
            empty={ready? and throughput(@metrics.result, operation) == 0}
            empty_label={dgettext("dashboard_builds", "No data")}
          />
        </div>
        <div data-part="filters">
          <.form
            id={@id <> "-search-form"}
            for={%{}}
            phx-change="search-cache-outputs"
            phx-submit="search-cache-outputs"
          >
            <.text_input
              type="search"
              id={@id <> "-search"}
              name="search"
              value={@params["cache-output-search"] || ""}
              placeholder={dgettext("dashboard_builds", "Search...")}
              show_suffix={false}
              phx-debounce="200"
              data-part="search"
            />
          </.form>
          <.dropdown
            id={@id <> "-sort"}
            label={
              if @params["cache-output-sort-by"] == "key",
                do: dgettext("dashboard_builds", "Key"),
                else: dgettext("dashboard_builds", "Size")
            }
            secondary_text={dgettext("dashboard_builds", "Sort by:")}
          >
            <.dropdown_item
              :for={
                {field, label} <- [
                  {"key", dgettext("dashboard_builds", "Key")},
                  {"size", dgettext("dashboard_builds", "Size")}
                ]
              }
              value={field}
              patch={"?#{@uri.query |> Query.put("cache-output-sort-by", field) |> Query.put("cache-output-page", "1")}"}
            >
              {label}
            </.dropdown_item>
          </.dropdown>
          <.dropdown id={@id <> "-filter"} label={dgettext("dashboard_builds", "Filter")}>
            <:icon><.filter /></:icon>
            <.dropdown_item
              :for={
                {operation, label} <- [
                  {"all", dgettext("dashboard", "All results")},
                  {"hit", dgettext("dashboard_builds", "Download")},
                  {"write", dgettext("dashboard_builds", "Upload")}
                ]
              }
              value={operation}
              patch={"?#{@uri.query |> Query.put("cache-output-operation", operation) |> Query.put("cache-output-page", "1")}"}
            >
              {label}
            </.dropdown_item>
          </.dropdown>
        </div>
        <.skeleton_chart :if={!ready?} />
        <.table
          :if={ready?}
          id={@id}
          rows={@outputs.result.rows}
          row_key={fn output -> @id <> "-" <> output.id end}
        >
          <:col
            :let={output}
            label={dgettext("dashboard_builds", "Key")}
            patch={"?#{Query.put(@uri.query, "cache-output-sort-order", if(@params["cache-output-sort-order"] == "asc", do: "desc", else: "asc")) |> Query.put("cache-output-sort-by", "key") |> Query.put("cache-output-page", "1")}"}
          >
            <.text_cell label={String.slice(output.action_digest, 0, 30) <> "..."} />
          </:col>
          <:col :let={output} label={dgettext("dashboard_builds", "Status")}>
            <.badge_cell
              label={
                if output.outcome == "hit",
                  do: dgettext("dashboard_builds", "Download"),
                  else: dgettext("dashboard_builds", "Upload")
              }
              color={if output.outcome == "hit", do: "focus", else: "secondary"}
              style="light-fill"
            />
          </:col>
          <:col label={dgettext("dashboard_builds", "Type")}>
            <.text_cell label={@artifact_type} />
          </:col>
          <:col
            :let={output}
            label={dgettext("dashboard_builds", "Size")}
            patch={"?#{Query.put(@uri.query, "cache-output-sort-order", if(@params["cache-output-sort-order"] == "asc", do: "desc", else: "asc")) |> Query.put("cache-output-sort-by", "size") |> Query.put("cache-output-page", "1")}"}
          >
            <.text_cell label={ByteFormatter.format_bytes(output.size)} />
          </:col>
          <:col label={dgettext("dashboard_builds", "Compressed Size")}>
            <.text_cell label="–" />
          </:col>
          <:col :let={output}>
            <.button_cell><:button><.button
              id={@id <> "-copy-" <> output.id}
              variant="secondary"
              size="small"
              icon_only
              phx-hook="Clipboard"
              data-clipboard-value={output.action_digest}
            ><.copy /></.button></:button></.button_cell>
          </:col>
          <:empty_state>
            <.table_empty_state
              icon="package"
              title={dgettext("dashboard_builds", "No CAS outputs found")}
              subtitle={
                dgettext(
                  "dashboard_builds",
                  "Only actual CAS transfers reported by Kura appear here. Local snapshot copies are not remote CAS outputs; compressed sizes are unavailable."
                )
              }
            />
          </:empty_state>
        </.table>
        <.pagination_group
          :if={ready? and @outputs.result.meta.total_pages > 1}
          current_page={@outputs.result.meta.current_page}
          number_of_pages={@outputs.result.meta.total_pages}
          page_patch={fn page -> "?#{Query.put(@uri.query, "cache-output-page", page)}" end}
        />
      </.card_section>
    </.async_card>
    """
  end

  defp throughput(metrics, "download"), do: metrics.content_download_throughput_bytes_per_second
  defp throughput(metrics, "upload"), do: metrics.content_upload_throughput_bytes_per_second

  defp chart_options do
    %{
      grid: %{width: "99%", left: "0%", height: "60%", top: "0%"},
      legend: %{
        show: true,
        left: "-0.3%",
        top: "bottom",
        orient: "horizontal",
        textStyle: %{
          color: "var:noora-surface-label-primary",
          fontFamily: "monospace",
          fontWeight: 400,
          fontSize: 10,
          lineHeight: 12
        },
        icon:
          "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.895431 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
        itemWidth: 8,
        itemHeight: 4
      },
      tooltip: %{trigger: "axis", axisPointer: %{type: "none"}},
      xAxis: %{type: "value", axisLabel: %{show: false}, splitLine: %{show: false}},
      yAxis: %{type: "category", data: [dgettext("dashboard_builds", "CAS outputs")], axisLabel: %{show: false}}
    }
  end

  defp series(metrics) do
    downloads = metrics.content_download_count
    uploads = metrics.content_upload_count

    [
      %{
        name: dgettext("dashboard_builds", "Download"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [downloads],
        color: "var:hits-chart-legend-remote",
        itemStyle: %{borderRadius: if(uploads > 0, do: [8, 0, 0, 8], else: [8, 8, 8, 8])}
      },
      %{
        name: dgettext("dashboard_builds", "Upload"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [uploads],
        color: "var:hits-chart-legend-local",
        itemStyle: %{borderRadius: if(downloads > 0, do: [0, 8, 8, 0], else: [8, 8, 8, 8])}
      }
    ]
  end
end
