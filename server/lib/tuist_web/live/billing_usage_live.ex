defmodule TuistWeb.BillingUsageLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton

  alias Tuist.Authorization
  alias Tuist.Billing
  alias Tuist.FeatureFlags
  alias Tuist.Kura.Usage

  @hourly_bucket_max_hours 36

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: current_user}} = socket) do
    if Authorization.authorize(:billing_update, current_user, account) != :ok or
         not FeatureFlags.kura_billing_enabled?(account) do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_usage", "The page you are looking for doesn't exist or has been moved.")
    end

    {:ok,
     socket
     |> assign(:billing_period, Billing.current_billing_period(account))
     |> assign(:cache_egress_price, Billing.cache_egress_price())
     |> assign(
       :head_title,
       "#{dgettext("dashboard_usage", "Cache billing")} · #{account.name} · Tuist"
     )}
  end

  @impl true
  def handle_params(
        _params,
        _uri,
        %{
          assigns: %{
            selected_account: account,
            billing_period: %{
              start_at: start_dt,
              end_at: end_dt,
              closes_at: closes_at,
              previous_start_at: previous_start_at,
              previous_end_at: previous_end_at
            }
          }
        } = socket
      ) do
    bucket = bucket_for_window(start_dt, end_dt)

    {:noreply,
     socket
     |> assign(:bucket, bucket)
     |> assign_async(:billing_usage, fn ->
       current = Usage.billable_egress_time_series(account.id, start_dt, end_dt, bucket: bucket)

       {:ok,
        %{
          billing_usage: %{
            current: current,
            previous_total: Usage.billable_egress_bytes(account.id, previous_start_at, previous_end_at),
            projected_total: Billing.projected_cache_egress_bytes(current.total, start_dt, closes_at, end_dt)
          }
        }}
     end)}
  end

  def chart_options(dates, bucket) do
    %{
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
      grid: %{width: "97%", left: "0.4%", height: "78%", top: "8%"},
      xAxis: %{
        boundaryGap: false,
        type: "category",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:toLocaleDate",
          customValues: [List.first(dates), List.last(dates)],
          padding: [10, 0, 0, 0]
        }
      },
      yAxis: %{
        splitNumber: 4,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "${value}"
        }
      },
      tooltip:
        if bucket == :hour do
          %{valueFormat: "${value}", dateFormat: "hour"}
        else
          %{valueFormat: "${value}"}
        end
    }
  end

  def chart_series(%{dates: dates, values: values}) do
    [
      %{
        color: "var:noora-chart-primary",
        data:
          dates
          |> Enum.zip(values)
          |> Enum.map(fn {date, bytes} -> [date, cost_value(bytes)] end),
        name: dgettext("dashboard_usage", "Cost to date"),
        type: "line",
        smooth: 0.1,
        symbol: "none"
      }
    ]
  end

  def format_cost(bytes) when is_integer(bytes) do
    bytes
    |> Billing.cache_egress_cost()
    |> format_cache_money()
  end

  def format_cache_money(%Money{} = money) do
    "$" <> TuistWeb.CldrHelpers.format_number(Money.to_decimal(money), fractional_digits: 2)
  end

  def format_date(%DateTime{} = date), do: Calendar.strftime(date, "%b %-d, %Y")

  def period_end(%DateTime{} = closes_at), do: DateTime.add(closes_at, -1, :second)

  defp cost_value(bytes) do
    bytes
    |> Billing.cache_egress_cost()
    |> Money.to_decimal()
    |> Decimal.to_float()
  end

  defp bucket_for_window(start_dt, end_dt) do
    if DateTime.diff(end_dt, start_dt, :hour) <= @hourly_bucket_max_hours, do: :hour, else: :day
  end
end
