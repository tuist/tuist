defmodule TuistWeb.Marketing.Components.IncrementalBuildLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      socket
      |> assign_new(:change, fn -> :leaf end)
      |> assign_new(:run, fn -> 0 end)
      |> recalculate()

    {:ok, socket}
  end

  def handle_event("change_task", %{"task" => task}, socket) do
    socket =
      socket
      |> assign(:change, String.to_existing_atom(task))
      |> update(:run, &(&1 + 1))
      |> recalculate()

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <section id={@id} class="incremental-build-lab">
      <.card icon="git_branch" title="What one change rebuilds">
        <:actions>
          <.button_group size="small">
            <.button_group_item
              label="A feature"
              data-selected={@change == :leaf}
              phx-click="change_task"
              phx-value-task="leaf"
              phx-target={@myself}
            />
            <.button_group_item
              label="A shared API"
              data-selected={@change == :shared}
              phx-click="change_task"
              phx-value-task="shared"
              phx-target={@myself}
            />
          </.button_group>
        </:actions>
        <.card_section>
          <div
            id={@id <> "-graph"}
            class="incremental-build-lab__graph"
            phx-hook="IncrementalBuildGraph"
            phx-update="ignore"
            data-change={@change}
            data-run={@run}
            aria-label={"A build graph showing the tasks invalidated by changing #{@change_label}"}
            role="img"
          />

          <p class="incremental-build-lab__summary">
            <strong>{@rebuild_count} tasks rerun</strong>
            <span>about {@rebuild_time} of work</span>
          </p>
        </.card_section>
      </.card>
    </section>
    """
  end

  defp recalculate(socket) do
    {invalidated, rebuild_time, change_label} =
      case socket.assigns.change do
        :leaf -> {[:leaf, :service, :app], "8 seconds", "a feature"}
        :shared -> {[:shared, :service, :tools, :app, :cli], "16 seconds", "a shared API"}
      end

    socket
    |> assign(:rebuild_count, length(invalidated))
    |> assign(:rebuild_time, rebuild_time)
    |> assign(:change_label, change_label)
  end
end
