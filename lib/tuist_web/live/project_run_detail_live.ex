defmodule TuistWeb.ProjectRunDetailLive do
  alias TuistWeb.ProjectRunDetailLive
  use TuistWeb, :live_view

  alias Tuist.Projects
  alias Tuist.CommandEvents

  on_mount {ProjectRunDetailLive, :assign_current_command_event}
  on_mount {TuistWeb.Authorization, [:current_user, :read, :command_event]}

  def on_mount(
        :assign_current_command_event,
        %{"id" => command_event_id} = _params,
        _session,
        socket
      ) do
    command_event =
      CommandEvents.get_command_event_by_id(command_event_id,
        preloads: [user: :account, project: :account]
      )

    if is_nil(command_event) do
      raise TuistWeb.Errors.NotFoundError,
            gettext("The page you are looking for doesn't exist or has been moved.")
    end

    socket =
      socket
      |> assign(:current_command_event, command_event)

    {:cont, socket}
  end

  def mount(
        _params,
        _session,
        %{assigns: %{selected_project: project, current_command_event: command_event}} = socket
      ) do
    local_cache_target_hits = command_event.local_cache_target_hits || []
    remote_cache_target_hits = command_event.remote_cache_target_hits || []

    cache_misses =
      command_event.cacheable_targets --
        (local_cache_target_hits ++ remote_cache_target_hits)

    cacheable_targets =
      (Enum.map(local_cache_target_hits, &%{name: &1, cache_hit: :local}) ++
         Enum.map(remote_cache_target_hits, &%{name: &1, cache_hit: :remote}) ++
         Enum.map(cache_misses, &%{name: &1, cache_hit: :miss}))
      |> Enum.sort_by(& &1.name)

    test_misses =
      command_event.test_targets --
        (command_event.local_test_target_hits ++ command_event.remote_test_target_hits)

    test_targets =
      (Enum.map(command_event.local_test_target_hits, &%{name: &1, cache_hit: :local}) ++
         Enum.map(command_event.remote_test_target_hits, &%{name: &1, cache_hit: :remote}) ++
         Enum.map(test_misses, &%{name: &1, cache_hit: :miss}))
      |> Enum.sort_by(& &1.name)

    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:head_title, "#{gettext("Run")} · #{slug} · Tuist")
      |> assign(:command_event, command_event)
      |> assign(:cache_misses, cache_misses)
      |> assign(:cacheable_targets, cacheable_targets)
      |> assign(:test_misses, test_misses)
      |> assign(:test_targets, test_targets)
      |> assign(:has_result_bundle, false)
      |> assign_async(:has_result_bundle, fn ->
        {:ok, %{has_result_bundle: CommandEvents.has_result_bundle?(command_event)}}
      end)
      |> assign_async([:test_summary, :test_target_results], fn ->
        test_summary = CommandEvents.get_test_summary(command_event)

        test_target_results =
          if is_nil(test_summary) do
            []
          else
            test_summary.project_tests
            |> Map.values()
            |> Enum.flat_map(&get_target_results(&1))
            |> Enum.sort_by(& &1.name)
          end

        {
          :ok,
          %{
            test_summary: test_summary,
            test_target_results: test_target_results
          }
        }
      end)
      |> assign(:test_target_results, [])
      |> assign(:test_summary, nil)
    }
  end

  defp get_target_results(targets_map) do
    Enum.map(targets_map, fn {target, target_test_summary} ->
      %{
        name: target,
        status: target_test_summary.status
      }
    end)
  end

  attr(:title, :string, required: true)
  slot(:inner_block, required: true, doc: "the inner block to present a custom value component")

  def run_detail_row(assigns) do
    ~H"""
    <.stack direction="horizontal" gap="9xl" class="run-detail__details__row">
      <span class="text--small font--semibold color--text-secondary run-detail__details__row__title">
        <%= @title %>
      </span>
      <span class="text--small font--regular color--text-primary run-detail__details__row__value">
        <%= render_slot(@inner_block) %>
      </span>
    </.stack>
    """
  end

  attr(:title, :string, required: true)
  attr(:id, :string, required: true)
  attr(:data, :list, required: true)
  attr(:labels, :list, required: true)
  attr(:colors, :list, default: [])
  attr(:total_label, :string, required: true)
  attr(:targets, :list, required: true)
  attr(:badge_column_label, :string, required: true)
  slot(:badge, required: true, doc: "the badge to present a custom value component")

  def target_breakdown_card(assigns) do
    ~H"""
    <.card class="run-detail__target-breakdown">
      <.stack gap="2xl">
        <.section_header title={@title} />
        <.stack direction="horizontal" class="run-detail__target-breakdown__content">
          <chart-l
            class="target-breakdown-chart"
            id={@id <> "-breakdown-chart"}
            type="donut"
            data-series={Jason.encode!(@data)}
            data-labels={Jason.encode!(@labels)}
            data-config={
              Jason.encode!(%{
                colors: @colors,
                totalLabel: @total_label,
                stroke: %{colors: ["--bg-secondary"]}
              })
            }
            phx-hook="Chart"
          >
          </chart-l>
          <.table
            class="run-detail__target-breakdown__table"
            id={@id}
            rows={@targets}
            empty_state_title={gettext("No targets")}
          >
            <:col :let={target} label={gettext("Name")}>
              <%= target.name %>
            </:col>
            <:col :let={target} label={@badge_column_label}>
              <div class="run-detail__target-breakdown__table__badge-container">
                <%= render_slot(@badge, target) %>
              </div>
            </:col>
          </.table>
        </.stack>
      </.stack>
    </.card>
    """
  end

  attr(:cache_hit, :atom, required: true)

  def cache_hit_badge(assigns) do
    ~H"""
    <.badge
      title={Atom.to_string(@cache_hit) |> String.capitalize()}
      kind={
        case @cache_hit do
          :local -> :brand_subtle
          :remote -> :brand
          :miss -> :warning
        end
      }
    />
    """
  end
end
