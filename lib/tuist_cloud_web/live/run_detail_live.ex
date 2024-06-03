defmodule TuistCloudWeb.RunDetailLive do
  use TuistCloudWeb, :live_view

  alias TuistCloud.CommandEvents

  def mount(params, _session, socket) do
    command_event = CommandEvents.get_command_event_by_id(params["id"])

    cache_misses =
      command_event.cacheable_targets --
        (command_event.local_cache_target_hits ++ command_event.remote_cache_target_hits)

    cacheable_targets =
      (Enum.map(command_event.local_cache_target_hits, &%{name: &1, cache_hit: :local}) ++
         Enum.map(command_event.remote_cache_target_hits, &%{name: &1, cache_hit: :remote}) ++
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

    {
      :ok,
      socket
      |> assign(:command_event, command_event)
      |> assign(:cache_misses, cache_misses)
      |> assign(:cacheable_targets, cacheable_targets)
      |> assign(:test_misses, test_misses)
      |> assign(:test_targets, test_targets)
      |> assign(:has_result_bundle, CommandEvents.has_result_bundle?(command_event))
    }
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
  attr(:targets, :list, required: true)

  def cache_hits_card(assigns) do
    ~H"""
    <.card class="run-detail__target-breakdown">
      <.stack gap="2xl">
        <.section_header title={@title} />
        <.stack direction="horizontal" class="run-detail__target-breakdown__content">
          <chart-l class="target-breakdown-chart" id={@id <> "-breakdown-chart"} type="donut">
          </chart-l>
          <.table class="run-detail__target-breakdown__table" id={@id} rows={@targets}>
            <:col :let={target} label={gettext("Name")}>
              <%= target.name %>
            </:col>
            <:col :let={target} label={gettext("Cache hit")}>
              <div class="run-detail__target-breakdown__table__badge-container">
                <.badge
                  title={Atom.to_string(target.cache_hit) |> String.capitalize()}
                  kind={
                    case target.cache_hit do
                      :local -> :brand_subtle
                      :remote -> :brand
                      :miss -> :warning
                    end
                  }
                />
              </div>
            </:col>
          </.table>
        </.stack>
      </.stack>
    </.card>
    """
  end
end
