defmodule TuistWeb.Components.CargoCacheInspection do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.Components.CacheBreakdown
  import TuistWeb.Components.CacheOutputList
  import TuistWeb.PercentileDropdownWidget

  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.Helpers.CargoCache
  alias TuistWeb.Utilities.Query

  attr :metrics, :map, required: true
  attr :section, :string, required: true
  attr :uri, :any, required: true
  attr :search, :string, required: true
  attr :sort, :string, required: true
  attr :status, :string, required: true
  attr :page, :integer, required: true
  attr :read_type, :string, required: true
  attr :write_type, :string, required: true

  def cargo_cache_inspection(assigns) do
    rows = CargoCache.rows(assigns.metrics, assigns.section)
    cas = CargoCache.rows(assigns.metrics, "cas-outputs")

    assigns =
      assign(assigns,
        rows: rows,
        details: assigns.metrics[:details],
        page_data: CargoCache.page(rows, assigns.search, assigns.sort, assigns.status, assigns.page),
        read: CargoCache.latency(rows, "read", assigns.read_type),
        write: CargoCache.latency(rows, "write", assigns.write_type),
        download: CargoCache.throughput(cas, "download"),
        upload: CargoCache.throughput(cas, "upload")
      )

    ~H"""
    <.card
      title={dgettext("dashboard_builds", "Cargo Cache")}
      icon="database"
      data-part="compilation-cache-card"
    >
      <.card_section data-part="compilation-cache-card-section">
        <.alert
          :if={@metrics.divergences > 0}
          status="warning"
          size="large"
          title={dgettext("dashboard_builds", "Cache verification detected divergent outputs")}
          description={
            dgettext(
              "dashboard_builds",
              "Fresh compiler outputs were retained instead of the divergent cached outputs."
            )
          }
        />
        <.alert
          :if={@details && @details.truncated}
          status="information"
          type="secondary"
          size="large"
          title={dgettext("dashboard_builds", "Cache inspection is incomplete")}
          description={
            dgettext(
              "dashboard_builds",
              "Inspection records are bounded and best-effort. The tables, charts and measurements below cover only captured records; the summary above retains the aggregate totals."
            )
          }
        />
        <.cache_breakdown
          id={
            if @section == "cas-outputs",
              do: "cargo-cas-outputs-breakdown-chart",
              else: "cargo-cache-actions-breakdown-chart"
          }
          label={
            cond do
              @section == "cas-outputs" -> dgettext("dashboard_builds", "CAS outputs:")
              is_nil(@details) -> dgettext("dashboard_builds", "Queried actions:")
              true -> dgettext("dashboard_builds", "Cacheable tasks:")
            end
          }
          segments={CargoCache.segments(@metrics, @section)}
        />
        <%= if @section == "cacheable-tasks" do %>
          <div data-part="latency-widgets">
            <.percentile_dropdown_widget
              id="widget-cargo-cache-read-latency"
              title={latency_title("read", @read_type)}
              description={
                dgettext(
                  "dashboard_builds",
                  "Measured per-key cache-agent lookup latency for recorded tasks, including local and remote resolution. Repeated reads of a key are averaged; cumulative build timings are not used as latency samples."
                )
              }
              value={@read.value}
              metrics={@read.metrics}
              selected_type={@read_type}
              event_name="select-cargo-cache-read-type"
              empty={@read.empty}
              empty_label={dgettext("dashboard_builds", "No data")}
            />
            <.percentile_dropdown_widget
              id="widget-cargo-cache-write-latency"
              title={latency_title("write", @write_type)}
              description={
                dgettext(
                  "dashboard_builds",
                  "Measured per-key cache-agent store latency for recorded tasks. This includes local storage and queueing, not completion of background remote publication. Repeated writes of a key are averaged."
                )
              }
              value={@write.value}
              metrics={@write.metrics}
              selected_type={@write_type}
              event_name="select-cargo-cache-write-type"
              empty={@write.empty}
              empty_label={dgettext("dashboard_builds", "No data")}
            />
          </div>
        <% else %>
          <div data-part="throughput-widgets">
            <.widget
              id="widget-cargo-download-throughput"
              title={dgettext("dashboard_builds", "Download throughput")}
              description={
                dgettext(
                  "dashboard_builds",
                  "Completed remote CAS bytes divided by their summed operation durations, including connection, retry and verification time. Operations can overlap; this is not whole-build network throughput."
                )
              }
              value={@download.value}
              empty={@download.empty}
              empty_label={dgettext("dashboard_builds", "No data")}
            />
            <.widget
              id="widget-cargo-upload-throughput"
              title={dgettext("dashboard_builds", "Upload throughput")}
              description={
                dgettext(
                  "dashboard_builds",
                  "Completed remote CAS bytes divided by their summed upload-attempt durations, including presence checks. Already-present blobs and failed attempts are excluded. Operations can overlap."
                )
              }
              value={@upload.value}
              empty={@upload.empty}
              empty_label={dgettext("dashboard_builds", "No data")}
            />
          </div>
        <% end %>
        <div data-part="filters">
          <.form
            for={%{}}
            id="cargo-cache-search-form"
            phx-change="search-cargo-cache"
            phx-debounce="200"
          >
            <.text_input
              type="search"
              id="search-cargo-cache"
              name="search"
              value={@search}
              placeholder={dgettext("dashboard_builds", "Search...")}
              show_suffix={false}
              data-part="search"
            />
          </.form>
          <.dropdown
            id="cargo-cache-sort"
            label={CargoCache.sort_label(@sort)}
            secondary_text={dgettext("dashboard_builds", "Sort by:")}
          >
            <.dropdown_item
              :for={sort <- CargoCache.sorts(@section)}
              value={sort}
              label={CargoCache.sort_label(sort)}
              patch={CargoCache.patch(@uri, @section, "sort", sort)}
              data-selected={@sort == sort}
            >
              <:right_icon><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
          <.dropdown
            id="cargo-cache-status-filter"
            label={
              if @status == "all",
                do: dgettext("dashboard_builds", "Filter"),
                else: CargoCache.status_label(@status)
            }
          >
            <:icon><.filter /></:icon>
            <.dropdown_item
              :for={status <- ["all" | CargoCache.statuses(@section)]}
              value={status}
              label={CargoCache.status_label(status)}
              patch={CargoCache.patch(@uri, @section, "status", status)}
              data-selected={@status == status}
            >
              <:right_icon><.check /></:right_icon>
            </.dropdown_item>
          </.dropdown>
        </div>
        <%= if @section == "cacheable-tasks" do %>
          <.table
            id="cacheable-tasks-table"
            rows={@page_data.rows}
            row_expandable={fn task -> CargoCache.references(task) != [] end}
          >
            <:col :let={task} label={dgettext("dashboard_builds", "Task")}>
              <.text_cell label={task.name} />
            </:col>
            <:col :let={task} label={dgettext("dashboard_builds", "Cache")}>
              <.tooltip
                id={"#{task.id}-status-tooltip"}
                title={CargoCache.status_description(task.status)}
              >
                <:trigger :let={attrs}>
                  <.badge_cell
                    label={CargoCache.status_label(task.status)}
                    color={CargoCache.color(task.status)}
                    style="light-fill"
                    tabindex="0"
                    {attrs}
                  />
                </:trigger>
              </.tooltip>
            </:col>
            <:col :let={task} label={dgettext("dashboard_builds", "Type")}>
              <.text_cell label={
                case task.kind do
                  "rust" -> "Rust"
                  "build_script" -> dgettext("dashboard_builds", "Build script")
                  _ -> dgettext("dashboard_builds", "Compiler")
                end
              } />
            </:col>
            <:col :let={task} label={dgettext("dashboard_builds", "Cache key")}>
              <.text_cell label={String.slice(task.key, 0, 30) <> "..."} />
            </:col>
            <:col :let={task}>
              <.button_cell><:button>
                <.button
                  id={"#{task.id}-copy"}
                  variant="secondary"
                  size="small"
                  icon_only
                  phx-hook="Clipboard"
                  data-clipboard-value={task.key}
                ><.copy /></.button>
              </:button></.button_cell>
            </:col>
            <:expanded_content :let={task}>
              <.cache_output_list
                id={"#{task.id}-outputs"}
                outputs={Enum.take(CargoCache.references(task), 50)}
              />
              <span :if={length(CargoCache.references(task)) > 50}>{dgettext(
                "dashboard_builds",
                "Showing the first 50 recorded CAS references."
              )}</span>
            </:expanded_content>
          </.table>
        <% else %>
          <.table id="cas-outputs-table" rows={@page_data.rows}>
            <:col :let={object} label={dgettext("dashboard_builds", "Key")}>
              <.text_cell label={String.slice(object.key, 0, 30) <> "..."} />
            </:col>
            <:col :let={object} label={dgettext("dashboard_builds", "Status")}>
              <.badge_cell
                label={CargoCache.status_label(object.status)}
                color={CargoCache.color(object.status)}
                style="light-fill"
              />
            </:col>
            <:col label={dgettext("dashboard_builds", "Type")}>
              <.text_cell label={dgettext("dashboard_builds", "Blob")} />
            </:col>
            <:col :let={object} label={dgettext("dashboard_builds", "Size")}>
              <.text_cell label={ByteFormatter.format_bytes(object.size_bytes)} />
            </:col>
            <:col :let={object} label={dgettext("dashboard_builds", "Duration")}>
              <.text_cell label={CargoCache.duration(object.duration_ns)} />
            </:col>
            <:col :let={object}>
              <.button_cell><:button>
                <.button
                  id={"#{object.id}-copy"}
                  variant="secondary"
                  size="small"
                  icon_only
                  phx-hook="Clipboard"
                  data-clipboard-value={object.key}
                ><.copy /></.button>
              </:button></.button_cell>
            </:col>
          </.table>
        <% end %>
        <.table_empty_state
          :if={@page_data.rows == []}
          title={
            cond do
              is_nil(@details) ->
                dgettext("dashboard_builds", "Detailed cache records were not collected")

              @section == "cas-outputs" ->
                dgettext("dashboard_builds", "No CAS outputs found")

              true ->
                dgettext("dashboard_builds", "No cacheable tasks found")
            end
          }
        />
        <.pagination_group
          :if={@page_data.pages > 1}
          current_page={@page_data.page}
          number_of_pages={@page_data.pages}
          page_patch={
            fn page ->
              "?#{Query.put(@uri.query, "#{CargoCache.prefix(@section)}-page", to_string(page))}"
            end
          }
        />
        <.alert
          status="information"
          type="secondary"
          size="large"
          title={dgettext("dashboard_builds", "Compiler work is not wall-clock time saved")}
          description={
            dgettext(
              "dashboard_builds",
              "Estimated compiler work avoided: %{duration}. Aggregate hits do not distinguish local and remote restores. CAS operations include protocol metadata and presence checks; they do not establish task restores. No remote CAS operations are inferred for local restores. Cumulative timings can overlap.",
              duration: CargoCache.duration(@metrics.estimated_compiler_duration_avoided_ns)
            )
          }
        />
      </.card_section>
    </.card>
    """
  end

  defp latency_title("read", type),
    do: dgettext("dashboard_builds", "%{percentile} latency reading cache keys", percentile: percentile_label(type))

  defp latency_title("write", type),
    do: dgettext("dashboard_builds", "%{percentile} latency writing cache keys", percentile: percentile_label(type))

  defp percentile_label("avg"), do: dgettext("dashboard", "Avg.")
  defp percentile_label(type), do: type
end
