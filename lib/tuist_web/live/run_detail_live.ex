defmodule TuistWeb.RunDetailLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Runs.RanByBadge

  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Xcode
  alias TuistWeb.Utilities.Query

  @table_page_size 20

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_run: run}} = socket) do
    run =
      Tuist.Repo.preload(
        run,
        user: :account,
        project: :account
      )

    slug = Projects.get_project_slug_from_id(project.id)

    selective_testing_analytics = Xcode.selective_testing_analytics(run)

    selective_testing_page_count =
      div(length(selective_testing_analytics.test_modules), @table_page_size) + 1

    binary_cache_analytics = Xcode.binary_cache_analytics(run)

    binary_cache_page_count =
      max(div(length(binary_cache_analytics.cacheable_targets), @table_page_size), 1)

    {:ok,
     socket
     |> assign(:run, run)
     |> assign(:head_title, "#{gettext("Run")} · #{slug} · Tuist")
     |> assign(:selective_testing_analytics, selective_testing_analytics)
     |> assign(:selective_testing_page_count, selective_testing_page_count)
     |> assign(:binary_cache_analytics, binary_cache_analytics)
     |> assign(:binary_cache_page_count, binary_cache_page_count)
     |> assign_async(:has_result_bundle, fn ->
       {:ok, %{has_result_bundle: CommandEvents.has_result_bundle?(run)}}
     end)}
  end

  def handle_params(
        params,
        _uri,
        %{
          assigns: %{
            selective_testing_analytics: selective_testing_analytics,
            binary_cache_analytics: binary_cache_analytics
          }
        } = socket
      ) do
    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, [
              "tab",
              "selective-testing-page",
              "selective-testing-sort-by",
              "selective-testing-sort-order",
              "binary-cache-page",
              "binary-cache-sort-by",
              "binary-cache-sort-order"
            ])
          )
      )

    selective_testing_filter = params["selective-testing-filter"] || ""
    selective_testing_page = String.to_integer(params["selective-testing-page"] || "1")
    selective_testing_sort_by = params["selective-testing-sort-by"] || "module"
    selective_testing_sort_order = params["selective-testing-sort-order"] || "desc"

    selective_testing_filtered_modules =
      Enum.filter(
        selective_testing_analytics.test_modules,
        &String.contains?(String.downcase(&1.name), String.downcase(selective_testing_filter))
      )

    selective_testing_page_count =
      max(div(length(selective_testing_filtered_modules), @table_page_size), 1)

    selective_testing_current_page_modules =
      selective_testing_filtered_modules
      |> sort_test_modules(
        selective_testing_sort_by,
        selective_testing_sort_order
      )
      |> Enum.slice(
        (selective_testing_page - 1) * @table_page_size,
        @table_page_size
      )

    binary_cache_filter = params["binary-cache-filter"] || ""
    binary_cache_page = String.to_integer(params["binary-cache-page"] || "1")
    binary_cache_sort_by = params["binary-cache-sort-by"] || "module"
    binary_cache_sort_order = params["binary-cache-sort-order"] || "desc"

    binary_cache_filtered_modules =
      Enum.filter(
        binary_cache_analytics.cacheable_targets,
        &String.contains?(String.downcase(&1.name), String.downcase(binary_cache_filter))
      )

    binary_cache_page_count =
      max(div(length(binary_cache_filtered_modules), @table_page_size), 1)

    binary_cache_current_page_modules =
      binary_cache_filtered_modules
      |> sort_binary_cache_modules(
        binary_cache_sort_by,
        binary_cache_sort_order
      )
      |> Enum.slice(
        (binary_cache_page - 1) * @table_page_size,
        @table_page_size
      )

    {
      :noreply,
      socket
      |> assign(:selected_tab, selected_tab(params))
      |> assign(:selective_testing_filter, selective_testing_filter)
      |> assign(
        :selective_testing_page,
        selective_testing_page
      )
      |> assign(:selective_testing_page_count, selective_testing_page_count)
      |> assign(
        :selective_testing_current_page_modules,
        selective_testing_current_page_modules
      )
      |> assign(
        :selective_testing_sort_by,
        selective_testing_sort_by
      )
      |> assign(
        :selective_testing_sort_order,
        selective_testing_sort_order
      )
      |> assign(:binary_cache_filter, binary_cache_filter)
      |> assign(
        :binary_cache_page,
        binary_cache_page
      )
      |> assign(:binary_cache_page_count, binary_cache_page_count)
      |> assign(
        :binary_cache_current_page_modules,
        binary_cache_current_page_modules
      )
      |> assign(
        :binary_cache_sort_by,
        binary_cache_sort_by
      )
      |> assign(
        :binary_cache_sort_order,
        binary_cache_sort_order
      )
      |> assign(:uri, uri)
    }
  end

  def handle_event("search-selective-testing", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/runs/#{socket.assigns.run.id}?#{Query.put(socket.assigns.uri.query, "selective-testing-filter", search)}"
      )

    {:noreply, socket}
  end

  def handle_event("search-binary-cache", %{"search" => search}, socket) do
    socket =
      push_patch(
        socket,
        to:
          "/#{socket.assigns.selected_account.name}/#{socket.assigns.selected_project.name}/runs/#{socket.assigns.run.id}?#{Query.put(socket.assigns.uri.query, "binary-cache-filter", search)}"
      )

    {:noreply, socket}
  end

  defp sort_test_modules(modules, "module", "asc") do
    Enum.sort_by(modules, & &1.name)
  end

  defp sort_test_modules(modules, "module", "desc") do
    Enum.sort_by(modules, & &1.name, :desc)
  end

  defp sort_test_modules(modules, "hash", "asc") do
    Enum.sort_by(modules, & &1.selective_testing_hit)
  end

  defp sort_test_modules(modules, "hash", "desc") do
    Enum.sort_by(modules, & &1.selective_testing_hit, :desc)
  end

  defp sort_test_modules(modules, _, _) do
    modules
  end

  defp sort_binary_cache_modules(modules, "module", "asc") do
    Enum.sort_by(modules, & &1.name)
  end

  defp sort_binary_cache_modules(modules, "module", "desc") do
    Enum.sort_by(modules, & &1.name, :desc)
  end

  defp sort_binary_cache_modules(modules, "hash", "asc") do
    Enum.sort_by(modules, & &1.selective_testing_hit)
  end

  defp sort_binary_cache_modules(modules, "hash", "desc") do
    Enum.sort_by(modules, & &1.selective_testing_hit, :desc)
  end

  defp sort_binary_cache_modules(modules, _, _) do
    modules
  end

  def sort_icon("desc") do
    "square_rounded_arrow_down"
  end

  def sort_icon("asc") do
    "square_rounded_arrow_up"
  end

  defp selected_tab(params) do
    tab = params["tab"]

    if is_nil(tab) do
      "overview"
    else
      tab
    end
  end

  def sort_order_patch_value(category, current_category, current_order) do
    if category == current_category do
      if current_order == "asc" do
        "desc"
      else
        "asc"
      end
    else
      "asc"
    end
  end
end
