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
     |> assign(
       :head_title,
       "#{dgettext("dashboard_usage", "Metered usage")} · #{account.name} · Tuist"
     )}
  end

  @impl true
  def handle_params(
        _params,
        _uri,
        %{assigns: %{selected_account: account, billing_period: %{start_at: start_dt, end_at: end_dt}}} = socket
      ) do
    bucket = bucket_for_window(start_dt, end_dt)

    {:noreply,
     socket
     |> assign(:bucket, bucket)
     |> assign_async(:billable_egress, fn ->
       {:ok,
        %{
          billable_egress: Usage.billable_egress_time_series(account.id, start_dt, end_dt, bucket: bucket)
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
          formatter: "fn:formatBytes"
        }
      },
      tooltip:
        if bucket == :hour do
          %{valueFormat: "fn:formatBytes", dateFormat: "hour"}
        else
          %{valueFormat: "fn:formatBytes"}
        end
    }
  end

  def chart_series(%{dates: dates, values: values}) do
    [
      %{
        color: "var:noora-chart-primary",
        data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1),
        name: dgettext("dashboard_usage", "Egress"),
        type: "line",
        smooth: 0.1,
        symbol: "none"
      }
    ]
  end

  defp bucket_for_window(start_dt, end_dt) do
    if DateTime.diff(end_dt, start_dt, :hour) <= @hourly_bucket_max_hours, do: :hour, else: :day
  end
end
