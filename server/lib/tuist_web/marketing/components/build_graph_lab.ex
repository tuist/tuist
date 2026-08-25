defmodule TuistWeb.Marketing.Components.BuildGraphLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  @task_work 10

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if_result =
      if Map.has_key?(socket.assigns, :graph_size) do
        socket
      else
        socket
        |> assign(:graph_size, 3)
        |> assign(:cores, 2)
        |> assign(:speed, 1)
      end

    socket = recalculate(if_result)

    {:ok, socket}
  end

  def handle_event("update_parameters", parameters, socket) do
    socket =
      socket
      |> assign(:graph_size, integer_parameter(parameters, "graph_size", socket.assigns.graph_size))
      |> assign(:cores, integer_parameter(parameters, "cores", socket.assigns.cores))
      |> assign(:speed, integer_parameter(parameters, "speed", socket.assigns.speed))
      |> recalculate()

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <style :type={TuistWeb.ColocatedCSS}>
      .build-graph-lab {
        display: flex;
        flex-direction: column;
        gap: var(--noora-spacing-6);
        margin: var(--noora-spacing-9) 0;
        width: min(780px, calc(100vw - var(--noora-spacing-12)));

        @media (min-width: 1024px) {
          margin-left: calc((650px - 780px) / 2);
        }
      }

      .build-graph-lab__controls,
      .build-graph-lab__diagrams {
        display: grid;
        gap: var(--noora-spacing-5);
      }

      .build-graph-lab__controls {
        grid-template-columns: repeat(2, minmax(0, 1fr));

        @media (min-width: 720px) {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
      }

      .build-graph-lab__range {
        display: grid;
        gap: var(--noora-spacing-2);
        color: var(--noora-surface-label-primary);
      }

      .build-graph-lab__range-label {
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .build-graph-lab__range-value {
        font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
      }

      .build-graph-lab__range input {
        cursor: pointer;
        margin: var(--noora-spacing-1) 0 0;
        width: 100%;
        accent-color: var(--noora-purple-500);
      }

      .build-graph-lab__result {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: var(--noora-spacing-3);
        color: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-medium);
      }

      .build-graph-lab__result strong {
        font: var(--noora-font-weight-semibold) var(--noora-font-body-medium);
      }

      .build-graph-lab__result span:last-child {
        color: var(--noora-surface-label-secondary);
      }

      .build-graph-lab__diagrams {
        grid-template-columns: 1fr;

        @media (min-width: 720px) {
          grid-template-columns: 1fr 1.4fr;
        }
      }

      .build-graph-lab svg {
        display: block;
        width: 100%;
        height: auto;
        overflow: visible;
        color: var(--noora-neutral-light-700);
      }

      .build-graph-lab__edge {
        stroke: currentColor;
        stroke-width: 2;
      }

      .build-graph-lab__node {
        fill: var(--noora-surface-background-primary);
        stroke: var(--noora-neutral-light-800);
        stroke-width: 2;
      }

      .build-graph-lab__node + text {
        fill: var(--noora-surface-label-primary);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .build-graph-lab__track {
        fill: var(--noora-neutral-light-300);
      }

      .build-graph-lab__task {
        fill: var(--noora-purple-500);
      }

      .build-graph-lab__task-label {
        fill: var(--noora-button-primary-label);
        font: var(--noora-font-weight-medium) var(--noora-font-body-small);
      }

      .build-graph-lab__core-label,
      .build-graph-lab__axis-label {
        fill: var(--noora-surface-label-secondary);
        font: var(--noora-font-weight-regular) var(--noora-font-body-small);
      }
    </style>

    <section id={@id} class="build-graph-lab">
      <.card icon="settings" title="Change the build">
        <.card_section>
          <form phx-change="update_parameters" phx-target={@myself} class="build-graph-lab__controls">
            <.range_control
              label="Tasks"
              name="graph_size"
              value={@graph_size}
              min="3"
              max="32"
              suffix=" tasks"
            />
            <.range_control
              label="Processor cores"
              name="cores"
              value={@cores}
              min="1"
              max="8"
              suffix=""
            />
            <.range_control
              label="Processor speed"
              name="speed"
              value={@speed}
              min="1"
              max="4"
              suffix="×"
            />
          </form>
        </.card_section>
      </.card>

      <div class="build-graph-lab__result">
        <span>Build time</span>
        <strong>{format_seconds(@build_time)}</strong>
        <span>{@ready_message}</span>
      </div>

      <div class="build-graph-lab__diagrams">
        <.card icon="git_branch" title="Task graph">
          <.card_section>
            <svg viewBox="0 0 360 205" role="img" aria-label="The selected task graph">
              <defs>
                <marker
                  id={@id <> "-arrow"}
                  markerWidth="8"
                  markerHeight="8"
                  refX="7"
                  refY="4"
                  orient="auto"
                >
                  <path d="M 0 0 L 8 4 L 0 8 z" fill="currentColor" />
                </marker>
              </defs>
              <line
                :for={edge <- @edges}
                x1={edge.x1}
                y1={edge.y1}
                x2={edge.x2}
                y2={edge.y2}
                class="build-graph-lab__edge"
                marker-end={if edge.arrow?, do: "url(##{@id}-arrow)"}
              />
              <g :for={task <- @graph_tasks} transform={"translate(#{task.x}, #{task.y})"}>
                <rect width={task.width} height={task.height} rx="8" class="build-graph-lab__node" />
                <text x={task.width / 2} y={task.height / 2 + 4} text-anchor="middle">
                  {task.label}
                </text>
              </g>
            </svg>
          </.card_section>
        </.card>

        <.card icon="clock_hour_4" title="Schedule">
          <.card_section>
            <svg
              viewBox={"0 0 520 #{50 + @cores * 42}"}
              role="img"
              aria-label="Processor core schedule"
            >
              <defs>
                <clipPath :for={core <- 1..@cores} id={"#{@id}-core-#{core}-clip"}>
                  <rect x="64" y={10 + (core - 1) * 42} width="430" height="30" rx="5" />
                </clipPath>
              </defs>
              <g :for={core <- 1..@cores}>
                <text x="0" y={31 + (core - 1) * 42} class="build-graph-lab__core-label">
                  core {core}
                </text>
                <rect
                  x="64"
                  y={10 + (core - 1) * 42}
                  width="430"
                  height="30"
                  rx="5"
                  class="build-graph-lab__track"
                />
              </g>
              <g :for={entry <- @schedule} clip-path={"url(##{@id}-core-#{entry.core}-clip)"}>
                <rect
                  x={64 + entry.start / @build_time * 430}
                  y={10 + (entry.core - 1) * 42}
                  width={max(entry.finish - entry.start, 0.2) / @build_time * 430}
                  height="30"
                  rx="0"
                  class="build-graph-lab__task"
                />
                <text
                  :if={entry.show_label?}
                  x={64 + (entry.start + entry.finish) / 2 / @build_time * 430}
                  y={31 + (entry.core - 1) * 42}
                  text-anchor="middle"
                  class="build-graph-lab__task-label"
                >
                  {entry.label}
                </text>
              </g>
              <text x="64" y={43 + @cores * 42} class="build-graph-lab__axis-label">0.0s</text>
              <text x="494" y={43 + @cores * 42} text-anchor="end" class="build-graph-lab__axis-label">
                {format_seconds(@build_time)}
              </text>
            </svg>
          </.card_section>
        </.card>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :integer, required: true
  attr :min, :string, required: true
  attr :max, :string, required: true
  attr :suffix, :string, default: " units"

  defp range_control(assigns) do
    ~H"""
    <label class="build-graph-lab__range">
      <span class="build-graph-lab__range-label">{@label}</span>
      <output class="build-graph-lab__range-value">{@value}{@suffix}</output>
      <input type="range" name={@name} value={@value} min={@min} max={@max} phx-debounce="100" />
    </label>
    """
  end

  defp recalculate(socket) do
    tasks = tasks(socket.assigns.graph_size)

    {schedule, build_time} = schedule(tasks, socket.assigns.cores, socket.assigns.speed)

    schedule =
      Enum.map(schedule, fn entry ->
        Map.put(entry, :show_label?, (entry.finish - entry.start) / build_time * 430 >= 48)
      end)

    {graph_tasks, edges} = graph(tasks)

    socket
    |> assign(:graph_tasks, graph_tasks)
    |> assign(:edges, edges)
    |> assign(:schedule, schedule)
    |> assign(:build_time, build_time)
    |> assign(:ready_message, ready_message(Enum.count(tasks, &Enum.empty?(&1.dependencies))))
  end

  defp tasks(task_count) do
    {tasks, _previous_ids, _next_index} =
      task_count
      |> layer_sizes()
      |> Enum.with_index()
      |> Enum.reduce({[], [], 1}, fn {layer_size, layer}, {tasks, previous_ids, next_index} ->
        layer_tasks =
          Enum.map(0..(layer_size - 1), fn index ->
            task_number = next_index + index

            %{
              id: "task-#{task_number}",
              label: "task #{task_number}",
              layer: layer,
              work: @task_work,
              dependencies: dependencies_for(previous_ids, layer_size, index)
            }
          end)

        {tasks ++ layer_tasks, Enum.map(layer_tasks, & &1.id), next_index + layer_size}
      end)

    tasks
  end

  defp layer_sizes(task_count) when task_count <= 6, do: [task_count - 1, 1]
  defp layer_sizes(task_count) when task_count <= 14, do: [task_count - 3, 2, 1]

  defp layer_sizes(task_count) do
    penultimate_size = max(2, div(task_count, 8))
    middle_size = max(3, div(task_count - penultimate_size - 1, 3))
    initial_size = task_count - middle_size - penultimate_size - 1

    [initial_size, middle_size, penultimate_size, 1]
  end

  defp dependencies_for([], _layer_size, _index), do: []

  defp dependencies_for(previous_ids, layer_size, index) do
    start_index = div(index * length(previous_ids), layer_size)
    end_index = div((index + 1) * length(previous_ids), layer_size)

    Enum.slice(previous_ids, start_index, end_index - start_index)
  end

  defp graph(tasks) do
    layers =
      tasks
      |> Enum.group_by(& &1.layer)
      |> Enum.sort_by(fn {layer, _tasks} -> layer end)

    layer_count = length(layers)
    node_width = node_width(layer_count)
    node_height = 24

    {nodes, node_by_id} =
      layers
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {{_layer, layer_tasks}, layer_index}, {nodes, node_by_id} ->
        displayed_tasks = displayed_tasks(layer_tasks)
        x = node_x(layer_index, layer_count, node_width)
        y = node_y(displayed_tasks, node_height)

        layer_nodes =
          displayed_tasks
          |> Enum.with_index()
          |> Enum.map(fn {task, index} ->
            graph_node(task, x, y + index * (node_height + 8), node_width, node_height)
          end)

        node_by_id =
          Enum.reduce(layer_nodes, node_by_id, fn node, node_by_id ->
            if node.id, do: Map.put(node_by_id, node.id, node), else: node_by_id
          end)

        {nodes ++ layer_nodes, node_by_id}
      end)

    edges =
      Enum.flat_map(tasks, fn task ->
        target = Map.get(node_by_id, task.id)

        sources =
          task.dependencies
          |> Enum.map(&Map.get(node_by_id, &1))
          |> Enum.reject(&is_nil/1)

        case {target, sources} do
          {nil, _} ->
            []

          {_, []} ->
            []

          {target, [source]} ->
            [graph_edge(source, target, true)]

          {target, [_ | _] = sources} ->
            merge_x = target.x - 16
            merge_y = target.y + target.height / 2

            Enum.map(sources, fn source ->
              graph_edge(source, %{x: merge_x, y: merge_y}, false)
            end) ++ [%{x1: merge_x, y1: merge_y, x2: target.x, y2: merge_y, arrow?: true}]
        end
      end)

    {nodes, edges}
  end

  defp displayed_tasks(tasks) do
    visible_tasks = Enum.take(tasks, 5)
    hidden_count = length(tasks) - length(visible_tasks)

    if hidden_count > 0 do
      visible_tasks ++ [%{id: nil, label: "+#{hidden_count} more"}]
    else
      visible_tasks
    end
  end

  defp node_width(2), do: 118
  defp node_width(3), do: 90
  defp node_width(_layer_count), do: 72

  defp node_x(layer_index, layer_count, node_width) do
    10 + layer_index * (340 - node_width) / max(layer_count - 1, 1)
  end

  defp node_y(tasks, node_height) do
    (205 - (length(tasks) * node_height + max(length(tasks) - 1, 0) * 8)) / 2
  end

  defp graph_node(task, x, y, width, height),
    do: %{id: task.id, label: task.label, x: x, y: y, width: width, height: height}

  defp graph_edge(source, target, arrow?) do
    target_y =
      case target do
        %{height: height} -> target.y + height / 2
        _ -> target.y
      end

    %{
      x1: source.x + source.width,
      y1: source.y + source.height / 2,
      x2: target.x,
      y2: target_y,
      arrow?: arrow?
    }
  end

  defp schedule(tasks, cores, speed), do: schedule(tasks, cores, speed, [], [], 0, [])

  defp schedule([], _cores, _speed, [], _completed, time, entries), do: {Enum.reverse(entries), time}

  defp schedule(pending, cores, speed, running, completed, time, entries) do
    busy_cores = MapSet.new(running, & &1.core)
    free_cores = Enum.reject(1..cores, &MapSet.member?(busy_cores, &1))

    {ready, waiting} =
      Enum.split_with(pending, fn task -> Enum.all?(task.dependencies, &(&1 in completed)) end)

    {started, remaining_ready} = Enum.split(ready, length(free_cores))

    new_running =
      started
      |> Enum.zip(free_cores)
      |> Enum.map(fn {task, core} ->
        Map.merge(task, %{core: core, start: time, finish: time + task.work / speed})
      end)

    running = running ++ new_running
    pending = remaining_ready ++ waiting

    next_finish = running |> Enum.map(& &1.finish) |> Enum.min()
    {finished, running} = Enum.split_with(running, &(&1.finish == next_finish))
    completed = completed ++ Enum.map(finished, & &1.id)

    entries =
      Enum.map(finished, fn task ->
        %{
          id: task.id,
          label: task.label,
          core: task.core,
          start: task.start,
          finish: task.finish
        }
      end) ++ entries

    schedule(pending, cores, speed, running, completed, next_finish, entries)
  end

  defp ready_message(1), do: "one task ready at the start"
  defp ready_message(2), do: "two tasks ready at the start"
  defp ready_message(task_count), do: "#{task_count} tasks ready at the start"

  defp integer_parameter(parameters, name, fallback) do
    case Integer.parse(Map.get(parameters, name, "")) do
      {value, ""} -> value
      _ -> fallback
    end
  end

  defp format_seconds(seconds), do: :erlang.float_to_binary(seconds * 1.0, decimals: 1) <> "s"
end
