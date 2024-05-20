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

    {
      :ok,
      socket
      |> assign(:command_event, command_event)
      |> assign(:cache_misses, cache_misses)
      |> assign(:cacheable_targets, cacheable_targets)
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
end
