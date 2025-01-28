defmodule TuistWeb.ProjectRunDetailLive do
  alias TuistWeb.ProjectRunDetailLive
  use TuistWeb, :live_view

  alias Tuist.Projects
  alias Tuist.CommandEvents
  alias Tuist.Repo

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
        preload: [user: :account, project: :account]
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
    command_event = Repo.preload(command_event, xcode_graph: [xcode_projects: :xcode_targets])

    %{
      cacheable_targets: cacheable_targets,
      binary_cache_local_hits_count: binary_cache_local_hits_count,
      binary_cache_remote_hits_count: binary_cache_remote_hits_count,
      binary_cache_misses_count: binary_cache_misses_count
    } = binary_cache_analytics(command_event)

    %{
      test_targets: test_targets,
      selective_testing_local_hits_count: selective_testing_local_hits_count,
      selective_testing_remote_hits_count: selective_testing_remote_hits_count,
      selective_testing_misses_count: selective_testing_misses_count
    } = selective_testing_analytics(command_event)

    slug = Projects.get_project_slug_from_id(project.id)

    {
      :ok,
      socket
      |> assign(:head_title, "#{gettext("Run")} · #{slug} · Tuist")
      |> assign(:command_event, command_event)
      |> assign(:cacheable_targets, cacheable_targets)
      |> assign(:binary_cache_local_hits_count, binary_cache_local_hits_count)
      |> assign(:binary_cache_remote_hits_count, binary_cache_remote_hits_count)
      |> assign(:binary_cache_misses_count, binary_cache_misses_count)
      |> assign(:selective_testing_local_hits_count, selective_testing_local_hits_count)
      |> assign(:selective_testing_remote_hits_count, selective_testing_remote_hits_count)
      |> assign(:selective_testing_misses_count, selective_testing_misses_count)
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

  # Deprecated way of obtaining binary cache analytics
  # Will be removed in the future
  defp binary_cache_analytics(command_event)
       when command_event.cacheable_targets != [] do
    local_cache_target_hits = command_event.local_cache_target_hits || []
    remote_cache_target_hits = command_event.remote_cache_target_hits || []

    cache_misses =
      command_event.cacheable_targets --
        (local_cache_target_hits ++ remote_cache_target_hits)

    cacheable_targets =
      (Enum.map(
         local_cache_target_hits,
         &%{name: &1, binary_cache_hit: :local, binary_cache_hash: nil}
       ) ++
         Enum.map(
           remote_cache_target_hits,
           &%{name: &1, binary_cache_hit: :remote, binary_cache_hash: nil}
         ) ++
         Enum.map(cache_misses, &%{name: &1, binary_cache_hit: :miss, binary_cache_hash: nil}))
      |> Enum.sort_by(& &1.name)

    %{
      cacheable_targets: cacheable_targets,
      binary_cache_local_hits_count: Enum.count(local_cache_target_hits),
      binary_cache_remote_hits_count: Enum.count(remote_cache_target_hits),
      binary_cache_misses_count: Enum.count(cache_misses)
    }
  end

  defp binary_cache_analytics(command_event) when not is_nil(command_event.xcode_graph) do
    cacheable_targets =
      command_event.xcode_graph.xcode_projects
      |> Enum.flat_map(& &1.xcode_targets)
      |> Enum.filter(&(not is_nil(&1.binary_cache_hash)))

    %{
      cacheable_targets: cacheable_targets,
      binary_cache_local_hits_count:
        cacheable_targets |> Enum.count(&(&1.binary_cache_hit == :local)),
      binary_cache_remote_hits_count:
        cacheable_targets |> Enum.count(&(&1.binary_cache_hit == :remote)),
      binary_cache_misses_count: cacheable_targets |> Enum.count(&(&1.binary_cache_hit == :miss))
    }
  end

  defp binary_cache_analytics(_command_event) do
    %{
      cacheable_targets: [],
      binary_cache_local_hits_count: 0,
      binary_cache_remote_hits_count: 0,
      binary_cache_misses_count: 0
    }
  end

  defp selective_testing_analytics(command_event) when not is_nil(command_event.xcode_graph) do
    test_targets =
      command_event.xcode_graph.xcode_projects
      |> Enum.flat_map(& &1.xcode_targets)
      |> Enum.filter(&(not is_nil(&1.selective_testing_hash)))

    %{
      test_targets: test_targets,
      selective_testing_local_hits_count:
        test_targets |> Enum.count(&(&1.selective_testing_hit == :local)),
      selective_testing_remote_hits_count:
        test_targets |> Enum.count(&(&1.selective_testing_hit == :remote)),
      selective_testing_misses_count:
        test_targets |> Enum.count(&(&1.selective_testing_hit == :miss))
    }
  end

  # Using deprecated columns
  defp selective_testing_analytics(command_event) when command_event.test_targets != [] do
    local_test_target_hits = command_event.local_test_target_hits || []
    remote_test_target_hits = command_event.remote_test_target_hits || []

    test_misses =
      command_event.test_targets --
        (local_test_target_hits ++ remote_test_target_hits)

    test_targets =
      (Enum.map(
         local_test_target_hits,
         &%{name: &1, selective_testing_hit: :local, selective_testing_hash: nil}
       ) ++
         Enum.map(
           remote_test_target_hits,
           &%{name: &1, selective_testing_hit: :remote, selective_testing_hash: nil}
         ) ++
         Enum.map(
           test_misses,
           &%{name: &1, selective_testing_hit: :miss, selective_testing_hash: nil}
         ))
      |> Enum.sort_by(& &1.name)

    %{
      test_targets: test_targets,
      selective_testing_local_hits_count: Enum.count(local_test_target_hits),
      selective_testing_remote_hits_count: Enum.count(remote_test_target_hits),
      selective_testing_misses_count: Enum.count(test_misses)
    }
  end

  defp selective_testing_analytics(_command_event) do
    %{
      test_targets: [],
      selective_testing_local_hits_count: 0,
      selective_testing_remote_hits_count: 0,
      selective_testing_misses_count: 0
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
        {@title}
      </span>
      <span class="text--small font--regular color--text-primary run-detail__details__row__value">
        {render_slot(@inner_block)}
      </span>
    </.stack>
    """
  end

  attr(:title, :string, required: true)
  attr(:id, :string, required: true)
  attr(:hash_key, :atom, required: false, default: nil)
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
              {target.name}
            </:col>
            <:col :let={target} label={@badge_column_label}>
              <div class="run-detail__target-breakdown__table__badge-container">
                {render_slot(@badge, target)}
              </div>
            </:col>
            <:col :let={target} :if={not is_nil(@hash_key)} label={gettext("Hash")}>
              {if is_nil(Map.get(target, @hash_key)) do
                gettext("Unknown")
              else
                Map.get(target, @hash_key)
              end}
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
