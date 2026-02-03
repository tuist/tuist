defmodule TuistWeb.Runs.ModuleCacheTab do
  @moduledoc """
  Shared component for the Module Cache tab used in both RunDetailLive and TestRunLive.
  """
  use TuistWeb, :html
  use Noora

  alias Tuist.Xcode
  alias TuistWeb.Utilities.Query

  attr :binary_cache_analytics, :map, required: true
  attr :binary_cache_filter, :string, required: true
  attr :binary_cache_page, :integer, required: true
  attr :binary_cache_page_count, :integer, required: true
  attr :binary_cache_sort_by, :string, required: true
  attr :binary_cache_sort_order, :string, required: true
  attr :expanded_target_names, :any, required: true
  attr :uri, :any, required: true
  attr :run, :any, required: true
  attr :available_filters, :list, required: true
  attr :binary_cache_active_filters, :list, required: true

  def module_cache_tab(assigns) do
    assigns = assign(assigns, :binary_cache_json, binary_cache_targets_json(assigns.run))

    ~H"""
    <div class="tuist-module-cache-tab">
      <.card
        title={dgettext("dashboard_builds", "Summary")}
        icon="chart_arcs"
        data-part="optimization-summary"
      >
        <.card_section data-part="optimization-summary-section">
          <.widget
            title={dgettext("dashboard_builds", "Cache hits")}
            description={
              dgettext(
                "dashboard_builds",
                "Total number of modules taken from either the local or the remote cache."
              )
            }
            value={
              @binary_cache_analytics.binary_cache_local_hits_count +
                @binary_cache_analytics.binary_cache_remote_hits_count
            }
            id="widget-optimization-summary-binary-cache-hits"
          />
          <.widget
            title={dgettext("dashboard_builds", "Cache misses")}
            description={
              dgettext(
                "dashboard_builds",
                "Total number of modules that could have been taken from the cache if it was fully populated."
              )
            }
            value={@binary_cache_analytics.binary_cache_misses_count}
            id="widget-optimization-summary-binary-cache-misses"
          />
          <.widget
            title={dgettext("dashboard_builds", "Cache hit rate")}
            description={
              dgettext(
                "dashboard_builds",
                "Percentage of modules that were successfully retrieved from the cache."
              )
            }
            value={"#{@binary_cache_analytics.cache_hit_rate}%"}
            id="widget-optimization-summary-cache-hit-rate"
          />
        </.card_section>
      </.card>
      <.card
        title={dgettext("dashboard_builds", "Module Cache")}
        icon="database"
        data-part="binary-cache"
      >
        <:actions>
          <.button
            id="copy-binary-cache-json"
            variant="secondary"
            label={dgettext("dashboard_builds", "Copy as JSON")}
            size="medium"
            phx-hook="Clipboard"
            data-clipboard-value={@binary_cache_json}
            disabled={Enum.empty?(@binary_cache_analytics.cacheable_targets)}
          >
            <:icon_left><.copy /></:icon_left>
          </.button>
        </:actions>
        <.card_section data-part="binary-cache-section">
          <.card_section
            :if={
              @binary_cache_analytics.binary_cache_local_hits_count +
                @binary_cache_analytics.binary_cache_remote_hits_count +
                @binary_cache_analytics.binary_cache_misses_count > 0
            }
            data-part="cacheable-targets-card-section"
          >
            <div data-part="title">
              <span data-part="label">
                {dgettext("dashboard_builds", "Cacheable targets:")}
              </span>
              <span data-part="value">
                {@binary_cache_analytics.binary_cache_local_hits_count +
                  @binary_cache_analytics.binary_cache_remote_hits_count +
                  @binary_cache_analytics.binary_cache_misses_count}
              </span>
            </div>
            <.chart
              id="cacheable-targets-breakdown-chart"
              type="bar"
              extra_options={cache_chart_options()}
              series={cache_chart_series(@binary_cache_analytics)}
              x_axis_min={0}
              x_axis_max={
                @binary_cache_analytics.binary_cache_local_hits_count +
                  @binary_cache_analytics.binary_cache_remote_hits_count +
                  @binary_cache_analytics.binary_cache_misses_count
              }
            />
          </.card_section>
          <div data-part="filters">
            <.form for={%{}} phx-change="search-binary-cache" phx-debounce="200">
              <.text_input
                type="search"
                id="search-binary-cache"
                name="search"
                placeholder={dgettext("dashboard_builds", "Search...")}
                show_suffix={false}
                data-part="search"
                value={@binary_cache_filter}
              />
            </.form>
            <.filter_dropdown
              id="binary-cache-filter-dropdown"
              label={dgettext("dashboard_builds", "Filter")}
              available_filters={@available_filters}
              active_filters={@binary_cache_active_filters}
            />
          </div>
          <div
            :if={Enum.any?(@binary_cache_active_filters)}
            data-part="active-filters"
          >
            <.active_filter :for={filter <- @binary_cache_active_filters} filter={filter} />
          </div>
          <.table
            id="binary-cache-table"
            rows={@binary_cache_analytics.cacheable_targets}
            row_key={fn target -> target.name end}
            row_expandable={fn target -> target.product_name != "" end}
            expanded_rows={MapSet.to_list(@expanded_target_names)}
          >
            <:col
              :let={binary_cache_module}
              label={dgettext("dashboard_builds", "Module")}
              patch={
                "?#{@uri.query
                |> Query.put("binary-cache-sort-by", "name")
                |> Query.put("binary-cache-sort-order", sort_order_patch_value("name", @binary_cache_sort_by, @binary_cache_sort_order))
                |> Query.drop("binary-cache-page")}"
              }
              icon={
                @binary_cache_sort_by == "name" &&
                  sort_icon(@binary_cache_sort_order)
              }
            >
              <.text_and_description_cell label={binary_cache_module.name} />
            </:col>
            <:col :let={binary_cache_module} label={dgettext("dashboard_builds", "Hit")}>
              <%= case binary_cache_module.binary_cache_hit do %>
                <% :remote -> %>
                  <.badge_cell
                    label={dgettext("dashboard_builds", "Remote")}
                    color="focus"
                    style="light-fill"
                  />
                <% :local -> %>
                  <.badge_cell
                    label={dgettext("dashboard_builds", "Local")}
                    color="secondary"
                    style="light-fill"
                  />
                <% :miss -> %>
                  <.badge_cell
                    label={dgettext("dashboard_builds", "Missed")}
                    color="warning"
                    style="light-fill"
                  />
              <% end %>
            </:col>
            <:col :let={binary_cache_module} label={dgettext("dashboard_builds", "Hash")}>
              <.text_cell label={
                binary_cache_module.binary_cache_hash || dgettext("dashboard_builds", "Unknown")
              } />
            </:col>
            <:expanded_content :let={target}>
              <.subhashes_list target={target} />
            </:expanded_content>
            <:empty_state>
              <.table_empty_state
                icon="database"
                title={dgettext("dashboard_builds", "No modules found")}
                subtitle={dgettext("dashboard_builds", "Try changing your search term")}
              />
            </:empty_state>
          </.table>
          <.pagination_group
            :if={@binary_cache_page_count > 1}
            current_page={@binary_cache_page}
            number_of_pages={@binary_cache_page_count}
            page_patch={
              fn page ->
                "?#{Query.put(@uri.query, "binary-cache-page", page)}"
              end
            }
          />
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :target, :map, required: true

  def subhashes_list(assigns) do
    ~H"""
    <div data-part="subhashes-list">
      <div :if={@target.product != ""} data-part="subhash-item">
        <span data-part="subhash-label">{dgettext("dashboard_builds", "Product")}:</span>
        <span data-part="subhash-value">{@target.product}</span>
      </div>
      <div :if={@target.product_name != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Product name")}:
        </span>
        <span data-part="subhash-value">{@target.product_name}</span>
      </div>
      <div :if={@target.bundle_id != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Bundle ID")}:
        </span>
        <span data-part="subhash-value">{@target.bundle_id}</span>
      </div>
      <div :if={not Enum.empty?(@target.destinations || [])} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Destinations")}:
        </span>
        <span data-part="subhash-value">
          {@target.destinations
          |> Enum.map(&Xcode.humanize_xcode_target_destination/1)
          |> Enum.join(", ")}
        </span>
      </div>
      <div :if={@target.external_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">{dgettext("dashboard_builds", "External")}:</span>
        <span data-part="subhash-value">{@target.external_hash}</span>
      </div>
      <div :if={@target.sources_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">{dgettext("dashboard_builds", "Sources")}:</span>
        <span data-part="subhash-value">{@target.sources_hash}</span>
      </div>
      <div :if={@target.resources_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Resources")}:
        </span>
        <span data-part="subhash-value">{@target.resources_hash}</span>
      </div>
      <div :if={@target.copy_files_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Copy files")}:
        </span>
        <span data-part="subhash-value">{@target.copy_files_hash}</span>
      </div>
      <div :if={@target.core_data_models_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Core data models")}:
        </span>
        <span data-part="subhash-value">{@target.core_data_models_hash}</span>
      </div>
      <div :if={@target.target_scripts_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Target scripts")}:
        </span>
        <span data-part="subhash-value">{@target.target_scripts_hash}</span>
      </div>
      <div :if={@target.environment_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Environment")}:
        </span>
        <span data-part="subhash-value">{@target.environment_hash}</span>
      </div>
      <div :if={@target.headers_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">{dgettext("dashboard_builds", "Headers")}:</span>
        <span data-part="subhash-value">{@target.headers_hash}</span>
      </div>
      <div :if={@target.deployment_target_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Deployment target")}:
        </span>
        <span data-part="subhash-value">{@target.deployment_target_hash}</span>
      </div>
      <div :if={@target.info_plist_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Info.plist")}:
        </span>
        <span data-part="subhash-value">{@target.info_plist_hash}</span>
      </div>
      <div :if={@target.entitlements_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Entitlements")}:
        </span>
        <span data-part="subhash-value">{@target.entitlements_hash}</span>
      </div>
      <div :if={@target.dependencies_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Dependencies")}:
        </span>
        <span data-part="subhash-value">{@target.dependencies_hash}</span>
      </div>
      <div :if={@target.project_settings_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Project settings")}:
        </span>
        <span data-part="subhash-value">{@target.project_settings_hash}</span>
      </div>
      <div :if={@target.target_settings_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Target settings")}:
        </span>
        <span data-part="subhash-value">{@target.target_settings_hash}</span>
      </div>
      <div :if={@target.buildable_folders_hash != ""} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Buildable folders")}:
        </span>
        <span data-part="subhash-value">{@target.buildable_folders_hash}</span>
      </div>
      <div :if={not Enum.empty?(@target.additional_strings || [])} data-part="subhash-item">
        <span data-part="subhash-label">
          {dgettext("dashboard_builds", "Additional strings")}:
        </span>
        <span data-part="subhash-value">
          {Enum.join(@target.additional_strings, ", ")}
        </span>
      </div>
    </div>
    """
  end

  defp sort_icon("desc"), do: "square_rounded_arrow_down"
  defp sort_icon("asc"), do: "square_rounded_arrow_up"

  defp sort_order_patch_value(category, current_category, current_order) do
    if category == current_category do
      if current_order == "asc", do: "desc", else: "asc"
    else
      "asc"
    end
  end

  defp cache_chart_options do
    %{
      tooltip: %{
        trigger: "axis",
        axisPointer: %{
          type: "none"
        }
      },
      legend: %{
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
          "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
        itemWidth: 8,
        itemHeight: 4
      },
      grid: %{
        width: "99%",
        left: "0%",
        height: "60%",
        top: "0%"
      },
      xAxis: %{
        type: "value",
        axisLabel: %{
          show: false
        },
        splitLine: %{show: false}
      },
      yAxis: %{
        type: "category",
        data: [dgettext("dashboard_builds", "Cacheable targets")],
        axisLabel: %{
          show: false
        }
      }
    }
  end

  defp cache_chart_series(binary_cache_analytics) do
    local_hits = binary_cache_analytics.binary_cache_local_hits_count
    remote_hits = binary_cache_analytics.binary_cache_remote_hits_count
    misses = binary_cache_analytics.binary_cache_misses_count

    [
      %{
        name: dgettext("dashboard_builds", "Local"),
        type: "bar",
        stack: "total",
        emphasis: %{
          focus: "series"
        },
        data: [local_hits],
        color: "var:hits-chart-legend-local",
        itemStyle: %{
          borderRadius: cache_chart_border_radius(local_hits, remote_hits, misses, :local)
        }
      },
      %{
        name: dgettext("dashboard_builds", "Remote"),
        type: "bar",
        stack: "total",
        emphasis: %{
          focus: "series"
        },
        data: [remote_hits],
        color: "var:hits-chart-legend-remote",
        itemStyle: %{
          borderRadius: cache_chart_border_radius(local_hits, remote_hits, misses, :remote)
        }
      },
      %{
        name: dgettext("dashboard_builds", "Missed"),
        type: "bar",
        stack: "total",
        emphasis: %{
          focus: "series"
        },
        data: [misses],
        color: "var:hits-chart-legend-missed",
        itemStyle: %{
          borderRadius: cache_chart_border_radius(local_hits, remote_hits, misses, :misses)
        }
      }
    ]
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp cache_chart_border_radius(local_hits, remote_hits, misses, position) do
    has_local = local_hits > 0
    has_remote = remote_hits > 0
    has_misses = misses > 0

    case {position, has_local, has_remote, has_misses} do
      {:local, true, false, false} -> [5, 5, 5, 5]
      {:local, true, _, _} -> [5, 0, 0, 5]
      {:remote, false, true, false} -> [5, 5, 5, 5]
      {:remote, true, true, false} -> [0, 5, 5, 0]
      {:remote, false, true, true} -> [5, 0, 0, 5]
      {:remote, true, true, true} -> [0, 0, 0, 0]
      {:misses, false, false, true} -> [5, 5, 5, 5]
      {:misses, _, _, true} -> [0, 5, 5, 0]
      _ -> [0, 0, 0, 0]
    end
  end

  defp binary_cache_targets_json(nil), do: "[]"

  defp binary_cache_targets_json(run) do
    run = Tuist.ClickHouseRepo.preload(run, [:xcode_targets])

    run.xcode_targets
    |> Enum.filter(&(&1.binary_cache_hash != nil))
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&target_to_json_map/1)
    |> Jason.encode!(pretty: true)
  end

  defp target_to_json_map(target) do
    %{
      name: target.name,
      binary_cache_hit: target.binary_cache_hit,
      binary_cache_hash: target.binary_cache_hash,
      product: target.product,
      bundle_id: target.bundle_id,
      product_name: target.product_name,
      external_hash: target.external_hash,
      sources_hash: target.sources_hash,
      resources_hash: target.resources_hash,
      copy_files_hash: target.copy_files_hash,
      core_data_models_hash: target.core_data_models_hash,
      target_scripts_hash: target.target_scripts_hash,
      environment_hash: target.environment_hash,
      headers_hash: target.headers_hash,
      deployment_target_hash: target.deployment_target_hash,
      info_plist_hash: target.info_plist_hash,
      entitlements_hash: target.entitlements_hash,
      dependencies_hash: target.dependencies_hash,
      project_settings_hash: target.project_settings_hash,
      target_settings_hash: target.target_settings_hash,
      buildable_folders_hash: target.buildable_folders_hash,
      destinations: target.destinations,
      additional_strings: target.additional_strings
    }
    |> Enum.reject(fn {_k, v} -> empty_value?(v) end)
    |> Map.new()
  end

  defp empty_value?(nil), do: true
  defp empty_value?(""), do: true
  defp empty_value?([]), do: true
  defp empty_value?(_), do: false
end
