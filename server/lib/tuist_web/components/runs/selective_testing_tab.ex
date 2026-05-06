defmodule TuistWeb.Runs.SelectiveTestingTab do
  @moduledoc """
  Shared component for the Selective Testing tab used in both RunDetailLive and TestRunLive.
  """
  use TuistWeb, :html
  use Noora

  alias Tuist.Xcode
  alias TuistWeb.Runs.ModuleCacheTab
  alias TuistWeb.Utilities.Query

  attr :selective_testing_analytics, :map, required: true
  attr :selective_testing_filter, :string, required: true
  attr :selective_testing_page, :integer, required: true
  attr :selective_testing_page_count, :integer, required: true
  attr :selective_testing_sort_by, :string, required: true
  attr :selective_testing_sort_order, :string, required: true
  attr :expanded_target_names, :any, required: true
  attr :uri, :any, required: true
  attr :run, :any, required: true

  def selective_testing_tab(assigns) do
    assigns = assign(assigns, :selective_testing_json, selective_testing_targets_json(assigns.run))

    ~H"""
    <div class="tuist-selective-testing-tab">
      <.card
        title={dgettext("dashboard_tests", "Optimization Summary")}
        icon="chart_arcs"
        data-part="optimization-summary"
      >
        <.card_section data-part="optimization-summary-section">
          <.widget
            title={dgettext("dashboard_tests", "Total modules")}
            description={
              dgettext(
                "dashboard_tests",
                "Total modules represents the total number of testable modules."
              )
            }
            value={@selective_testing_analytics.total_modules_count}
            id="widget-optimization-summary-total-modules"
          />
          <.widget
            title={dgettext("dashboard_tests", "Selective test hits")}
            description={
              dgettext(
                "dashboard_tests",
                "Selective test hits represents the number of test modules that were skipped thanks to the selective testing."
              )
            }
            value={
              @selective_testing_analytics.selective_testing_local_hits_count +
                @selective_testing_analytics.selective_testing_remote_hits_count
            }
            id="widget-optimization-summary-selective-test-hits"
          />
          <.widget
            title={dgettext("dashboard_tests", "Selective test misses")}
            description={
              dgettext(
                "dashboard_tests",
                "Selective test misses represents the number of test modules that were run as they were not successfully run before."
              )
            }
            value={@selective_testing_analytics.selective_testing_misses_count}
            id="widget-optimization-summary-selective-test-misses"
          />
        </.card_section>
      </.card>
      <.card
        title={dgettext("dashboard_tests", "Selective Testing")}
        icon="history_toggle"
        data-part="selective-testing"
      >
        <:actions>
          <.button
            id="copy-selective-testing-json"
            variant="secondary"
            label={dgettext("dashboard_tests", "Copy as JSON")}
            size="medium"
            phx-hook="Clipboard"
            data-clipboard-value={@selective_testing_json}
            disabled={Enum.empty?(@selective_testing_analytics.test_modules)}
          >
            <:icon_left><.copy /></:icon_left>
          </.button>
        </:actions>
        <.card_section data-part="selective-testing-section">
          <.form for={%{}} phx-change="search-selective-testing" phx-debounce="200">
            <.text_input
              type="search"
              id="search-selective-testing"
              name="search"
              placeholder={dgettext("dashboard_tests", "Search...")}
              show_suffix={false}
              data-part="search"
              value={@selective_testing_filter}
            />
          </.form>
          <.table
            id="selective-testing-table"
            rows={@selective_testing_analytics.test_modules}
            row_key={fn test_module -> test_module.name end}
            row_expandable={fn test_module -> has_subhashes?(test_module) end}
            expanded_rows={MapSet.to_list(@expanded_target_names)}
          >
            <:col
              :let={test_module}
              label={dgettext("dashboard_tests", "Module")}
              patch={
                "?#{@uri.query
                |> Query.put("selective-testing-sort-by", "name")
                |> Query.put("selective-testing-sort-order", sort_order_patch_value("name", @selective_testing_sort_by, @selective_testing_sort_order))
                |> Query.drop("selective-testing-page")}"
              }
              icon={
                @selective_testing_sort_by == "name" &&
                  sort_icon(@selective_testing_sort_order)
              }
            >
              <.text_and_description_cell label={test_module.name} />
            </:col>
            <:col :let={test_module} label={dgettext("dashboard_tests", "Hit")}>
              <.badge_cell
                :if={test_module.selective_testing_hit == :remote}
                label={dgettext("dashboard_tests", "Remote")}
                color="focus"
                style="light-fill"
              />
              <.badge_cell
                :if={test_module.selective_testing_hit == :local}
                label={dgettext("dashboard_tests", "Local")}
                color="secondary"
                style="light-fill"
              />
              <.badge_cell
                :if={test_module.selective_testing_hit == :miss}
                label={dgettext("dashboard_tests", "Missed")}
                color="warning"
                style="light-fill"
              />
            </:col>
            <:col :let={test_module} label={dgettext("dashboard_tests", "Hash")}>
              <.text_cell label={
                test_module.selective_testing_hash || dgettext("dashboard_tests", "Unknown")
              } />
            </:col>
            <:expanded_content :let={test_module}>
              <ModuleCacheTab.subhashes_list target={test_module} />
            </:expanded_content>
            <:empty_state>
              <.table_empty_state
                icon="history_toggle"
                title={dgettext("dashboard_tests", "No modules found")}
                subtitle={dgettext("dashboard_tests", "Try changing your search term")}
              />
            </:empty_state>
          </.table>
          <.pagination_group
            :if={@selective_testing_page_count > 1}
            current_page={@selective_testing_page}
            number_of_pages={@selective_testing_page_count}
            page_patch={
              fn page ->
                "?#{Query.put(@uri.query, "selective-testing-page", page)}"
              end
            }
          />
        </.card_section>
      </.card>
    </div>
    """
  end

  defp has_subhashes?(test_module) do
    Enum.any?(
      [
        :sources_hash,
        :resources_hash,
        :copy_files_hash,
        :core_data_models_hash,
        :target_scripts_hash,
        :environment_hash,
        :headers_hash,
        :deployment_target_hash,
        :info_plist_hash,
        :entitlements_hash,
        :dependencies_hash,
        :project_settings_hash,
        :target_settings_hash,
        :buildable_folders_hash,
        :external_hash
      ],
      fn key -> Map.get(test_module, key, "") not in [nil, ""] end
    ) or
      not Enum.empty?(Map.get(test_module, :additional_strings, []) || []) or
      not Enum.empty?(Map.get(test_module, :destinations, []) || []) or
      Map.get(test_module, :product, "") not in [nil, ""] or
      Map.get(test_module, :product_name, "") not in [nil, ""] or
      Map.get(test_module, :bundle_id, "") not in [nil, ""]
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

  defp selective_testing_targets_json(nil), do: "[]"

  defp selective_testing_targets_json(run) do
    run = Tuist.ClickHouseRepo.preload(run, xcode_targets: Xcode.xcode_targets_preload_query(run))

    run.xcode_targets
    |> Enum.filter(&(&1.selective_testing_hash != nil))
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&target_to_json_map/1)
    |> Jason.encode!(pretty: true)
  end

  defp target_to_json_map(target) do
    %{
      name: target.name,
      selective_testing_hit: target.selective_testing_hit,
      selective_testing_hash: target.selective_testing_hash,
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
