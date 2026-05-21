defmodule TuistWeb.PercentileDropdownWidget do
  @moduledoc """
  Convenience wrapper around `TuistWeb.MetricDropdownWidget` that wires up the
  standard percentile options (`avg`, `p99`, `p90`, `p50`). Callers pass a
  `metrics` map keyed by atom (`:avg`, `:p99`, `:p90`, `:p50`) and a
  `selected_type` string; everything else passes through to the underlying
  widget.

  ## Example

      <.percentile_dropdown_widget
        id="latency-widget"
        title="Latency"
        description="Response time"
        value="125ms"
        metrics={%{avg: "100ms", p99: "250ms", p90: "180ms", p50: "95ms"}}
        selected_type="p99"
        event_name="change_percentile"
        legend_color="p99"
      />
  """
  use TuistWeb, :html
  use Noora

  import Phoenix.Component
  import TuistWeb.MetricDropdownWidget

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:description, :string, required: true)
  attr(:value, :string, default: nil)
  attr(:metrics, :map, default: nil)
  attr(:selected_type, :string, required: true, values: ~w(avg p99 p90 p50))
  attr(:event_name, :string, required: true)
  attr(:loading, :boolean, default: false)
  attr(:empty, :boolean, default: false)
  attr(:empty_label, :string, default: nil)
  attr(:legend_color, :string, default: nil)
  attr(:selected, :boolean, default: false)
  attr(:trend_value, :any, default: nil)
  attr(:trend_type, :atom, default: :regular, values: [:regular, :inverse, :neutral])
  attr(:trend_label, :string, default: nil)
  attr(:phx_click, :string, default: nil)
  attr(:phx_value_widget, :string, default: nil)

  def percentile_dropdown_widget(assigns) do
    assigns =
      assigns
      |> assign(:options, percentile_options())
      |> update(:metrics, &stringify_metric_keys/1)

    ~H"""
    <.metric_dropdown_widget
      id={@id}
      title={@title}
      description={@description}
      value={@value}
      options={@options}
      metrics={@metrics}
      selected_type={@selected_type}
      event_name={@event_name}
      loading={@loading}
      empty={@empty}
      empty_label={@empty_label}
      legend_color={@legend_color}
      selected={@selected}
      trend_value={@trend_value}
      trend_type={@trend_type}
      trend_label={@trend_label}
      phx_click={@phx_click}
      phx_value_widget={@phx_value_widget}
    />
    """
  end

  defp percentile_options do
    [
      %{value: "avg", label: dgettext("dashboard", "Avg."), dot_type: "avg"},
      %{value: "p99", label: dgettext("dashboard", "p99"), dot_type: "p99"},
      %{value: "p90", label: dgettext("dashboard", "p90"), dot_type: "p90"},
      %{value: "p50", label: dgettext("dashboard", "p50"), dot_type: "p50"}
    ]
  end

  defp stringify_metric_keys(nil), do: nil

  defp stringify_metric_keys(metrics) when is_map(metrics) do
    Map.new(metrics, fn {k, v} -> {to_string(k), v} end)
  end
end
