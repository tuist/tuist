defmodule AtlasWeb.Admin.InferenceHelpers do
  @moduledoc false

  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Inference
  alias Atlas.Inference.ModelBinding
  alias Atlas.Inference.Token

  attr :summary, :map, required: true

  def usage_widgets(assigns) do
    ~H"""
    <div data-part="widgets">
      <.metric_widget
        id="inference-requests-widget"
        title={gettext("Requests")}
        value={format_count(@summary.request_count)}
        legend_color="tertiary"
      />
      <.metric_widget
        id="inference-input-tokens-widget"
        title={gettext("Input tokens")}
        value={format_count(@summary.input_tokens)}
        legend_color="primary"
      />
      <.metric_widget
        id="inference-output-tokens-widget"
        title={gettext("Output tokens")}
        value={format_count(@summary.output_tokens)}
        legend_color="secondary"
      />
      <.metric_widget
        id="inference-cost-widget"
        title={gettext("Estimated cost")}
        value={format_cost(@summary.cost_usd)}
        legend_color="p50"
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :legend_color, :string, required: true

  def metric_widget(assigns) do
    ~H"""
    <.card_section id={@id} class="tuist-widget">
      <div data-part="header">
        <div data-part="legend" data-color={@legend_color}></div>
        <span data-part="title">{@title}</span>
      </div>
      <span data-part="value">{@value}</span>
    </.card_section>
    """
  end

  attr :id, :string, required: true
  attr :selected_preset, :string, required: true
  attr :period, :any, required: true
  attr :name, :string, default: "usage-date-range"

  def usage_period_picker(assigns) do
    ~H"""
    <div data-part="date-picker-bar">
      <.date_picker
        id={@id}
        name={@name}
        presets={usage_period_presets()}
        selected_preset={@selected_preset}
        period={@period}
        on_period_change="usage_period_changed"
        max={Date.utc_today()}
      >
        <:actions>
          <.button
            label={gettext("Cancel")}
            variant="secondary"
            phx-click={
              Phoenix.LiveView.JS.dispatch("phx:date-picker-cancel", detail: %{id: @id})
            }
          />
          <.button
            label={gettext("Apply")}
            phx-click={
              Phoenix.LiveView.JS.dispatch("phx:date-picker-apply", detail: %{id: @id})
            }
          />
        </:actions>
      </.date_picker>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :series, :list, required: true
  attr :preset, :string, required: true
  attr :bucket, :atom, required: true
  attr :label, :string, required: true

  def usage_chart(assigns) do
    ~H"""
    <div data-part="usage-chart">
      <.chart
        id={@id}
        type="line"
        series={usage_chart_series(@series)}
        extra_options={usage_chart_options(@series, @preset, @bucket)}
        y_axis_min={0}
        aria-label={@label}
      />
    </div>
    """
  end

  def usage_chart_has_usage?(series), do: Enum.any?(series, &(&1.total_tokens > 0))

  def provider_select_options(current_provider \\ nil) do
    Inference.list_provider_configs()
    |> Enum.filter(& &1.configured?)
    |> Enum.map(&provider_select_option/1)
    |> maybe_include_current_provider(current_provider)
    |> Enum.uniq_by(& &1.value)
  end

  def model_identifier_placeholder(provider) do
    case normalize_provider(provider) do
      provider when provider in ["fireworks", "fireworks-ai", "fireworks_ai"] ->
        "accounts/fireworks/models/kimi-k2p5"

      "openai" ->
        "gpt-4o-mini"

      provider when provider in ["togetherai", "together-ai", "together_ai", "together"] ->
        "MiniMaxAI/MiniMax-M3"

      provider when provider != "" ->
        "model-id"

      _provider ->
        "gpt-4o-mini"
    end
  end

  def atlas_role_badges(%ModelBinding{} = profile) do
    []
    |> maybe_add_atlas_role(profile.atlas_inference, %{
      label: gettext("Atlas inference"),
      color: "primary"
    })
    |> maybe_add_atlas_role(profile.atlas_coding, %{
      label: gettext("Atlas coding"),
      color: "primary"
    })
    |> maybe_add_atlas_role(profile.atlas_embedding, %{
      label: gettext("Atlas embeddings"),
      color: "secondary"
    })
    |> Enum.reverse()
  end

  def atlas_usage_label(%ModelBinding{} = profile) do
    case {profile.atlas_inference, profile.atlas_coding, profile.atlas_embedding} do
      {true, true, true} -> gettext("Inference, coding, and embeddings")
      {true, true, false} -> gettext("Inference and coding")
      {true, false, true} -> gettext("Inference and embeddings")
      {false, true, true} -> gettext("Coding and embeddings")
      {true, false, false} -> gettext("Inference")
      {false, true, false} -> gettext("Coding")
      {false, false, true} -> gettext("Embeddings")
      {false, false, false} -> gettext("Not used by Atlas")
    end
  end

  def profile_status(%ModelBinding{enabled: true}),
    do: %{label: gettext("Enabled"), color: "success"}

  def profile_status(%ModelBinding{}),
    do: %{label: gettext("Disabled"), color: "neutral"}

  def token_status(%Token{enabled: false}),
    do: %{label: gettext("Revoked"), color: "neutral"}

  def token_status(%Token{expires_at: %DateTime{} = expires_at}) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
      %{label: gettext("Active"), color: "success"}
    else
      %{label: gettext("Expired"), color: "warning"}
    end
  end

  def token_status(%Token{}),
    do: %{label: gettext("Active"), color: "success"}

  def token_expiry_table_label(nil), do: gettext("Never expires")
  def token_expiry_table_label(%DateTime{} = at), do: format_compact_datetime(at)

  def last_used_label(nil), do: gettext("Never used")
  def last_used_label(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  def format_compact_datetime(%DateTime{} = at), do: Calendar.strftime(at, "%b %d, %H:%M")

  def empty_usage_summary do
    %{
      request_count: 0,
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      cost_usd: Decimal.new(0)
    }
  end

  defp maybe_add_atlas_role(roles, true, role), do: [role | roles]
  defp maybe_add_atlas_role(roles, _enabled, _role), do: roles

  def usage_period_from_params(params) do
    usage_period(params["usage-date-range"] || params["usage-period"], params)
  end

  def usage_period(nil), do: usage_period("last-30-days")
  def usage_period("last-24-hours"), do: {"last-24-hours", relative_period(-24, :hour)}
  def usage_period("last-7-days"), do: {"last-7-days", relative_period(-7, :day)}
  def usage_period("last-12-months"), do: {"last-12-months", relative_period(-365, :day)}
  def usage_period("custom"), do: usage_period("last-30-days")
  def usage_period(_preset), do: {"last-30-days", relative_period(-30, :day)}

  def usage_period("custom", params) do
    case custom_period(params) do
      {:ok, period} -> {"custom", period}
      :error -> usage_period("last-30-days")
    end
  end

  def usage_period(preset, _params), do: usage_period(preset)

  def usage_period_bucket(preset, period \\ nil)
  def usage_period_bucket("last-24-hours", _period), do: :hour
  def usage_period_bucket("last-12-months", _period), do: :month

  def usage_period_bucket("custom", {start_at, end_at}) do
    cond do
      DateTime.diff(end_at, start_at, :hour) <= 48 -> :hour
      DateTime.diff(end_at, start_at, :day) > 92 -> :month
      true -> :day
    end
  end

  def usage_period_bucket(_preset, _period), do: :day

  def usage_period_presets do
    [
      %{
        id: "last-24-hours",
        label: gettext("Last 24 hours"),
        period: {24, :hour}
      },
      %{
        id: "last-7-days",
        label: gettext("Last 7 days"),
        period: {7, :day}
      },
      %{
        id: "last-30-days",
        label: gettext("Last 30 days"),
        period: {30, :day}
      },
      %{
        id: "last-12-months",
        label: gettext("Last 12 months"),
        period: {12, :month}
      },
      %{id: "custom", label: gettext("Custom")}
    ]
  end

  def usage_period_label(preset) do
    usage_period_presets()
    |> Enum.find_value(gettext("Last 30 days"), fn option ->
      if option.id == preset, do: option.label
    end)
  end

  def format_count(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/.{3}(?=.)/, "\\0,")
    |> String.reverse()
  end

  def format_count(_value), do: "0"

  def format_cost(%Decimal{} = value) do
    if Decimal.equal?(value, Decimal.new(0)) do
      "$0.00"
    else
      "$#{value |> Decimal.round(6) |> Decimal.to_string(:normal) |> trim_cost_decimals()}"
    end
  end

  def format_cost(_value), do: "$0.00"

  def format_cost_per_million(nil), do: gettext("Not configured")

  def format_cost_per_million(value) do
    gettext("%{cost} / million tokens", cost: format_cost(value))
  end

  defp usage_chart_series(series) do
    [
      %{
        color: "var:noora-chart-primary",
        data: usage_chart_points(series, :input_tokens),
        name: gettext("Input"),
        smooth: 0.1
      },
      %{
        color: "var:noora-chart-secondary",
        data: usage_chart_points(series, :output_tokens),
        name: gettext("Output"),
        smooth: 0.1
      }
    ]
  end

  defp usage_chart_points(series, key) do
    Enum.map(series, fn point ->
      [DateTime.to_iso8601(point.bucket), Map.fetch!(point, key)]
    end)
  end

  defp usage_chart_options(series, _preset, bucket) do
    dates = Enum.map(series, &DateTime.to_iso8601(&1.bucket))

    %{
      grid: %{
        height: "78%",
        left: "0.4%",
        top: "8%",
        width: "97%"
      },
      legend: %{
        left: "left",
        top: "bottom",
        orient: "horizontal",
        textStyle: %{
          color: "var:noora-surface-label-secondary",
          fontFamily: "monospace",
          fontWeight: 400,
          fontSize: 10,
          lineHeight: 12
        },
        icon:
          "path://M0 6C0 4.89543 0.895431 4 2 4H6C7.10457 4 8 4.89543 8 6C8 7.10457 7.10457 8 6 8H2C0.895431 8 0 7.10457 0 6Z",
        itemWidth: 8,
        itemHeight: 4
      },
      tooltip: %{
        dateFormat: tooltip_date_format(bucket)
      },
      xAxis: %{
        boundaryGap: false,
        type: "category",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          customValues: usage_chart_edge_dates(dates),
          formatter: x_axis_formatter(bucket),
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        splitNumber: 4,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{
          color: "var:noora-surface-label-secondary"
        }
      }
    }
  end

  defp usage_chart_edge_dates([]), do: []
  defp usage_chart_edge_dates([date]), do: [date]
  defp usage_chart_edge_dates(dates), do: [List.first(dates), List.last(dates)]

  defp x_axis_formatter(:hour), do: "fn:toLocaleDateHour"
  defp x_axis_formatter(_bucket), do: "fn:toLocaleDate"

  defp tooltip_date_format(:hour), do: "hour"
  defp tooltip_date_format(_bucket), do: nil

  defp custom_period(params) do
    with {:ok, start_at} <- parse_datetime(params["usage-start-date"]),
         {:ok, end_at} <- parse_datetime(params["usage-end-date"]),
         true <- DateTime.compare(start_at, end_at) == :lt do
      {:ok, {start_at, end_at}}
    else
      _ -> :error
    end
  end

  defp parse_datetime(nil), do: :error

  defp parse_datetime(value) do
    with {:error, _reason} <- DateTime.from_iso8601(value),
         {:ok, date} <- Date.from_iso8601(value),
         {:ok, datetime} <- DateTime.new(date, ~T[00:00:00], "Etc/UTC") do
      {:ok, datetime}
    else
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      _ -> :error
    end
  end

  defp relative_period(amount, unit) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {DateTime.add(now, amount, unit), now}
  end

  defp trim_cost_decimals(value) do
    case String.split(value, ".", parts: 2) do
      [whole] ->
        whole <> ".00"

      [whole, decimals] ->
        decimals = String.trim_trailing(decimals, "0")

        cond do
          decimals == "" -> whole <> ".00"
          String.length(decimals) == 1 -> whole <> "." <> decimals <> "0"
          true -> whole <> "." <> decimals
        end
    end
  end

  defp provider_select_option(%{id: id, source: :reference}) do
    %{label: gettext("%{id} (not configured)", id: id), value: id}
  end

  defp provider_select_option(%{id: id}), do: %{label: id, value: id}

  defp normalize_provider(provider) when is_binary(provider), do: String.trim(provider)
  defp normalize_provider(nil), do: ""
  defp normalize_provider(provider), do: provider |> to_string() |> String.trim()

  defp maybe_include_current_provider(options, provider)
       when is_binary(provider) and provider != "" do
    if Enum.any?(options, &(&1.value == provider)) do
      options
    else
      [provider_select_option(%{id: provider, source: :reference}) | options]
    end
  end

  defp maybe_include_current_provider(options, _provider), do: options
end
