defmodule TuistWeb.Marketing.Components.CacheTransferLab do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  @sample_sizes [1, 8, 64, 256, 512]
  @chart_width 420

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      socket
      |> assign_new(:artifact_size, fn -> 64 end)
      |> assign_new(:request_rounds, fn -> 3 end)
      |> assign_new(:latency, fn -> 30 end)
      |> assign_new(:bandwidth, fn -> 100 end)
      |> recalculate()

    {:ok, socket}
  end

  def handle_event("update_parameters", parameters, socket) do
    socket =
      socket
      |> assign(:artifact_size, integer_parameter(parameters, "artifact_size", socket.assigns.artifact_size))
      |> assign(:request_rounds, integer_parameter(parameters, "request_rounds", socket.assigns.request_rounds))
      |> assign(:latency, integer_parameter(parameters, "latency", socket.assigns.latency))
      |> assign(:bandwidth, integer_parameter(parameters, "bandwidth", socket.assigns.bandwidth))
      |> recalculate()

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <section id={@id} class="cache-transfer-lab" data-part="cache-transfer-lab">
      <.card icon="chart_dots" title="What a cache hit costs">
        <.card_section>
          <form
            phx-change="update_parameters"
            phx-target={@myself}
            class="cache-transfer-lab__controls"
          >
            <.range_control
              label="Artifact size"
              name="artifact_size"
              value={@artifact_size}
              min="1"
              max="512"
              suffix=" megabytes"
            />
            <.range_control
              label="Request rounds"
              name="request_rounds"
              value={@request_rounds}
              min="1"
              max="8"
              suffix={request_rounds_suffix(@request_rounds)}
            />
            <.range_control
              label="Cache latency"
              name="latency"
              value={@latency}
              min="1"
              max="200"
              suffix=" milliseconds"
            />
            <.range_control
              label="Bandwidth"
              name="bandwidth"
              value={@bandwidth}
              min="25"
              max="500"
              suffix=" megabytes per second"
            />
          </form>
        </.card_section>

        <.card_section>
          <div class="cache-transfer-lab__summary" aria-live="polite">
            <span>A cache hit for {@artifact_size} megabytes takes at least</span>
            <strong>{@selected_duration}</strong>
            <span>{@latency_duration} waiting · {@transfer_duration} transferring</span>
          </div>

          <div class="cache-transfer-lab__legend" aria-hidden="true">
            <span>
              <i class="cache-transfer-lab__legend-swatch cache-transfer-lab__legend-swatch--latency" />waiting for requests
            </span>
            <span>
              <i class="cache-transfer-lab__legend-swatch cache-transfer-lab__legend-swatch--transfer" />moving bytes
            </span>
          </div>

          <svg
            class="cache-transfer-lab__chart"
            viewBox="0 0 650 230"
            role="img"
            aria-labelledby={@id <> "-chart-title " <> @id <> "-chart-description"}
          >
            <title id={@id <> "-chart-title"}>
              How artifact size, latency, and bandwidth affect a cache hit
            </title>
            <desc id={@id <> "-chart-description"}>{@chart_description}</desc>
            <defs>
              <clipPath :for={row <- @rows} id={"#{@id}-bar-#{row.index}-clip"}>
                <rect x="150" y={row.y} width={@chart_width} height="22" rx="6" />
              </clipPath>
            </defs>
            <g
              :for={row <- @rows}
              class={
                if row.selected?,
                  do: "cache-transfer-lab__sample cache-transfer-lab__sample--selected",
                  else: "cache-transfer-lab__sample"
              }
            >
              <text x="0" y={row.y + 16} class="cache-transfer-lab__sample-label">
                {format_size(row.size)}
              </text>
              <rect
                x="150"
                y={row.y}
                width={@chart_width}
                height="22"
                rx="6"
                class="cache-transfer-lab__track"
              />
              <g clip-path={"url(##{@id}-bar-#{row.index}-clip)"}>
                <rect
                  x="150"
                  y={row.y}
                  width={row.latency_width}
                  height="22"
                  class="cache-transfer-lab__latency"
                />
                <rect
                  x={150 + row.latency_width}
                  y={row.y}
                  width={row.transfer_width}
                  height="22"
                  class="cache-transfer-lab__transfer"
                />
              </g>
              <text x="650" y={row.y + 16} text-anchor="end" class="cache-transfer-lab__duration">
                {row.duration}
              </text>
            </g>
          </svg>

          <div class="cache-transfer-lab__mobile-samples">
            <div :for={row <- @rows} class="cache-transfer-lab__mobile-sample">
              <div class="cache-transfer-lab__mobile-sample-header">
                <strong :if={row.selected?}>{format_size(row.size)}</strong>
                <span :if={!row.selected?}>{format_size(row.size)}</span>
                <strong :if={row.selected?}>{row.duration}</strong>
                <span :if={!row.selected?}>{row.duration}</span>
              </div>
              <div class="cache-transfer-lab__mobile-bar">
                <span
                  class="cache-transfer-lab__latency"
                  style={"width: #{row.latency_percent}%"}
                />
                <span
                  class="cache-transfer-lab__transfer"
                  style={"width: #{row.transfer_percent}%"}
                />
              </div>
            </div>
          </div>

          <p class="cache-transfer-lab__explanation">
            The purple waiting time is the same in every row. The transfer time grows with artifact size.
          </p>
        </.card_section>
      </.card>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :integer, required: true
  attr :min, :string, required: true
  attr :max, :string, required: true
  attr :suffix, :string, required: true

  defp range_control(assigns) do
    ~H"""
    <label class="cache-transfer-lab__range">
      <span class="cache-transfer-lab__range-label">{@label}</span>
      <output class="cache-transfer-lab__range-value">{@value}{@suffix}</output>
      <input type="range" name={@name} value={@value} min={@min} max={@max} phx-debounce="100" />
    </label>
    """
  end

  defp recalculate(socket) do
    samples = (@sample_sizes ++ [socket.assigns.artifact_size]) |> Enum.uniq() |> Enum.sort()
    latency_time = latency_time(socket.assigns.request_rounds, socket.assigns.latency)

    sample_timings =
      Enum.map(samples, fn size ->
        transfer_time = transfer_time(size, socket.assigns.bandwidth)

        %{
          size: size,
          latency_time: latency_time,
          transfer_time: transfer_time,
          total_time: latency_time + transfer_time
        }
      end)

    maximum_time = sample_timings |> Enum.map(& &1.total_time) |> Enum.max()

    rows =
      sample_timings
      |> Enum.with_index()
      |> Enum.map(fn {timing, index} ->
        %{
          index: index,
          size: timing.size,
          y: 14 + index * 38,
          latency_width: @chart_width * timing.latency_time / maximum_time,
          transfer_width: @chart_width * timing.transfer_time / maximum_time,
          latency_percent: 100 * timing.latency_time / maximum_time,
          transfer_percent: 100 * timing.transfer_time / maximum_time,
          duration: format_duration(timing.total_time),
          selected?: timing.size == socket.assigns.artifact_size
        }
      end)

    selected_transfer_time = transfer_time(socket.assigns.artifact_size, socket.assigns.bandwidth)
    selected_total_time = latency_time + selected_transfer_time

    socket
    |> assign(:chart_width, @chart_width)
    |> assign(:rows, rows)
    |> assign(:latency_duration, format_duration(latency_time))
    |> assign(:transfer_duration, format_duration(selected_transfer_time))
    |> assign(:selected_duration, format_duration(selected_total_time))
    |> assign(
      :chart_description,
      "Each bar shows the lower-bound time for retrieving an artifact. #{socket.assigns.request_rounds} request rounds at #{socket.assigns.latency} milliseconds create the same waiting time in every row. At #{socket.assigns.bandwidth} megabytes per second, larger artifacts take longer to transfer."
    )
  end

  defp latency_time(request_rounds, latency), do: request_rounds * latency
  defp transfer_time(artifact_size, bandwidth), do: artifact_size / bandwidth * 1000

  defp request_rounds_suffix(1), do: " request round"
  defp request_rounds_suffix(_request_rounds), do: " request rounds"

  defp format_size(1), do: "1 megabyte"
  defp format_size(size), do: "#{size} megabytes"

  defp format_duration(milliseconds) when milliseconds < 1000, do: "#{round(milliseconds)} milliseconds"

  defp format_duration(milliseconds), do: :erlang.float_to_binary(milliseconds / 1000, decimals: 1) <> " seconds"

  defp integer_parameter(parameters, name, fallback) do
    case Integer.parse(Map.get(parameters, name, "")) do
      {value, ""} -> value
      _ -> fallback
    end
  end
end
