defmodule TuistWeb.UsageLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.Billing
  alias Tuist.Billing.UsagePricing
  alias Tuist.FeatureFlags
  alias Tuist.Kura.Usage
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Prepaid
  alias Tuist.Utilities.ByteFormatter
  alias TuistWeb.CldrHelpers
  alias TuistWeb.Utilities.Query

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: current_user}} = socket) do
    if Authorization.authorize(:account_dashboard_read, current_user, account) != :ok do
      raise TuistWeb.Errors.NotFoundError,
            dgettext("dashboard_usage", "The page you are looking for doesn't exist or has been moved.")
    end

    runner_breakdown = Allowance.period_breakdown(account)
    runners_enabled = FeatureFlags.runners_enabled?(account)

    # Twelve is enough history to look back a year without listing
    # periods the account did not exist for; empty ones simply report
    # nothing.
    periods = Billing.recent_billing_periods(account, 12)

    # Read once and kept, because `handle_params/3` runs on every period
    # change and `Prepaid.balance/2` does not cache a nil: an account
    # with no credit would otherwise pay a Stripe round trip each time.
    prepaid_balance = Prepaid.balance(account)

    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard_usage", "Usage")} · #{account.name} · Tuist")
     |> assign(:periods, periods)
     |> assign(:runner_breakdown, runner_breakdown)
     |> assign(:runners_enabled, runners_enabled)
     |> assign(:usage_based_pricing, FeatureFlags.usage_based_pricing_enabled?(account))
     |> assign(:cache_view, "charge")
     |> assign(:prepaid_balance, prepaid_balance)}
  end

  @widgets ["egress", "ingress", "requests"]
  @cache_views ["charge", "egress", "requests"]

  @impl true
  def handle_params(
        params,
        uri,
        %{
          assigns: %{
            selected_account: account,
            periods: periods,
            prepaid_balance: prepaid_balance,
            usage_based_pricing: usage_based_pricing
          }
        } = socket
      ) do
    period = selected_period(periods, params["period"])
    selected_widget = widget_param(params["widget"])

    runner_breakdown = Allowance.period_breakdown(account, period)

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:analytics_period, period)
     |> assign(:selected_period, period)
     |> assign(:bucket, :day)
     |> assign(:analytics_selected_widget, selected_widget)
     |> assign(:analytics_trend_label, dgettext("dashboard_usage", "since the previous period"))
     |> assign(:runner_breakdown, runner_breakdown)
     |> assign(:prepaid_coverage, period_coverage(prepaid_balance, runner_breakdown, period == hd(periods)))
     |> assign_usage_pricing(usage_based_pricing, account, period)
     |> assign_cache_traffic(usage_based_pricing, account, period)}
  end

  defp assign_cache_traffic(socket, true, _account, _period), do: socket

  defp assign_cache_traffic(socket, false, account, {start_dt, end_dt}) do
    # The page reports one billing period, so the cache traffic beside
    # the runner usage is scoped to the same window rather than to a
    # range of its own. Daily buckets: a period is a month, and an hourly
    # bucket over a month is unreadable.
    base_opts = [bucket: :day]
    egress_opts = Keyword.merge(base_opts, direction: "egress", metric: :bytes)
    ingress_opts = Keyword.merge(base_opts, direction: "ingress", metric: :bytes)
    requests_opts = Keyword.put(base_opts, :metric, :requests)

    usage_end = if DateTime.before?(DateTime.utc_now(), end_dt), do: DateTime.utc_now(), else: end_dt

    assign_async(
      socket,
      [:totals, :egress_series, :ingress_series, :requests_series, :per_region],
      fn ->
        {:ok,
         %{
           totals: Usage.totals(account.id, start_dt, usage_end, base_opts),
           egress_series: Usage.traffic_time_series_by_region(account.id, start_dt, usage_end, egress_opts),
           ingress_series: Usage.traffic_time_series_by_region(account.id, start_dt, usage_end, ingress_opts),
           requests_series: Usage.traffic_time_series_by_region(account.id, start_dt, usage_end, requests_opts),
           per_region: Usage.per_region(account.id, start_dt, usage_end, base_opts)
         }}
      end
    )
  end

  defp assign_usage_pricing(socket, false, _account, _period), do: assign(socket, :usage_pricing, nil)

  defp assign_usage_pricing(socket, true, account, period) do
    assign_async(socket, :usage_pricing, fn ->
      {:ok, %{usage_pricing: UsagePricing.period_breakdown(account, period)}}
    end)
  end

  # A prepaid balance is what the account holds today, so it describes
  # only the period still being accrued. The grants that covered a closed
  # period were drawn down when it was invoiced, and today's balance says
  # nothing about what that invoice came to, so a closed period reports
  # its usage charge and no credit at all.
  defp period_coverage(_balance, _breakdown, false), do: nil
  defp period_coverage(balance, breakdown, true), do: prepaid_coverage(balance, breakdown)

  @doc """
  The period whose start matches the `period` param, or the current one.
  """
  def selected_period(periods, nil), do: hd(periods)

  def selected_period(periods, param) do
    Enum.find(periods, hd(periods), fn {period_start, _} ->
      Date.to_iso8601(DateTime.to_date(period_start)) == param
    end)
  end

  def period_param({period_start, _}), do: Date.to_iso8601(DateTime.to_date(period_start))

  def period_patch(uri, period) do
    query =
      uri.query
      |> Kernel.||("")
      |> URI.decode_query()
      |> Map.put("period", period_param(period))
      |> URI.encode_query()

    "#{uri.path}?#{query}"
  end

  def period_label({period_start, period_end}) do
    "#{Timex.format!(period_start, "{Mshort} {D}")} – #{Timex.format!(period_end, "{Mshort} {D}, {YYYY}")}"
  end

  @impl true
  def handle_event("select_cache_view", %{"widget" => view}, socket) do
    {:noreply, assign(socket, :cache_view, cache_view_param(view))}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, push_patch_with_param(socket, "widget", widget)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("usage-date-range", "custom")
        |> Query.put("usage-start-date", start_date)
        |> Query.put("usage-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "usage-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{socket.assigns.selected_account.name}/usage?#{query_params}")}
  end

  defp push_patch_with_param(socket, key, value) do
    query = Query.put(socket.assigns.uri.query || "", key, value)
    push_patch(socket, to: "/#{socket.assigns.selected_account.name}/usage?#{query}")
  end

  defp cache_view_param(view) when view in @cache_views, do: view
  defp cache_view_param(_view), do: "charge"

  defp widget_param(widget) when widget in @widgets, do: widget
  defp widget_param(_), do: "egress"

  @doc """
  echarts `extra_options` for the traffic chart. The y-axis + tooltip
  formatter depend on which widget is selected: bytes for egress/ingress,
  raw count for requests.
  """
  def traffic_chart_options(dates, selected_widget) do
    {axis_formatter, tooltip_format} = formatters_for(selected_widget)

    %{
      legend: chart_legend(),
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
          formatter: axis_formatter
        }
      },
      # Always daily now: the window is a billing period, so there is no
      # hourly preset left to format for.
      tooltip: tooltip_format
    }
  end

  defp chart_legend do
    %{
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
    }
  end

  defp formatters_for("requests"), do: {nil, %{}}
  defp formatters_for(_), do: {"fn:formatBytes", %{valueFormat: "fn:formatBytes"}}

  @doc """
  Picks the right series for the currently selected widget so the template
  doesn't have to branch on three different async assigns.
  """
  def series_for(socket_assigns, "egress"), do: socket_assigns.egress_series
  def series_for(socket_assigns, "ingress"), do: socket_assigns.ingress_series
  def series_for(socket_assigns, "requests"), do: socket_assigns.requests_series

  @region_colors ["primary", "secondary", "tertiary", "p50", "p90", "p99", "warning", "destructive"]

  @doc """
  Builds one echarts series per region. Stable-orders regions by total bytes
  so the colour assignment stays consistent across patches that don't change
  the data, but freshest legend chips first when traffic shifts.
  """
  def traffic_chart_series(time_series) do
    time_series
    |> Enum.with_index()
    |> Enum.map(fn {%{region: region, dates: dates, values: values}, idx} ->
      color_key = Enum.at(@region_colors, rem(idx, length(@region_colors)))

      %{
        color: "var:noora-chart-#{color_key}",
        data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1),
        name: region_label(region),
        type: "line",
        smooth: 0.1,
        symbol: "none"
      }
    end)
  end

  @doc """
  Every date the runner chart draws, spend and projection alike.

  The axis labels only its first and last date, so it has to know about
  the days still ahead; derived from spend alone it stopped at today.
  """
  def runner_chart_dates(breakdown) do
    (breakdown.by_repository ++ breakdown.projected_days)
    |> Enum.map(& &1.date)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  @doc """
  Chart options for the runner spend series. Dollars on the y axis, not
  bytes, and a date x axis spanning the billing month.
  """
  def runner_chart_options(dates) do
    %{
      # Repositories are named in the tooltip; a legend repeats them and
      # steals height from a chart that is only 280px tall.
      legend: %{show: false},
      # `containLabel` lets the grid reserve whatever the axis labels
      # need. Currency labels are wider than the byte labels the traffic
      # chart uses, and a fixed left inset clipped the leading symbol.
      # `containLabel` reserves room for the labels themselves; the
      # insets are the breathing space around them, without which the
      # leading currency symbol and the outermost dates sit flush
      # against the edge and get clipped.
      grid: %{left: 12, right: 16, top: 16, bottom: 12, containLabel: true},
      xAxis: %{
        boundaryGap: false,
        type: "category",
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: "fn:toLocaleDate",
          customValues: [List.first(dates), List.last(dates)],
          padding: [6, 0, 0, 0]
        }
      },
      yAxis: %{
        splitNumber: 4,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary", formatter: "fn:formatCurrency"}
      },
      tooltip: %{valueFormat: "fn:formatCurrency"}
    }
  end

  @repository_colors ["primary", "secondary", "tertiary", "quaternary", "p50", "p90", "p99"]

  @doc """
  One stacked bar series per repository, valued in dollars.

  Stacked rather than overlaid: the reader's question is where a
  period's spend went, so the bars have to sum to the period's total
  and each segment has to be comparable against the others in the same
  day.
  """
  def runner_chart_series(by_repository, projected_days \\ []) do
    dates =
      (by_repository ++ projected_days)
      |> Enum.map(& &1.date)
      |> Enum.uniq()
      |> Enum.sort(Date)

    by_repository
    |> Enum.group_by(& &1.repository)
    |> Enum.sort_by(fn {_repository, rows} -> -Enum.sum(Enum.map(rows, & &1.total_ms)) end)
    |> Enum.with_index()
    |> Enum.map(fn {{repository, rows}, index} ->
      per_day = Map.new(rows, &{&1.date, &1.total_ms})

      %{
        color: "var:noora-chart-#{Enum.at(@repository_colors, rem(index, length(@repository_colors)))}",
        data: Enum.map(dates, fn date -> [date, dollars(Map.get(per_day, date, 0))] end),
        name: repository_label(repository),
        type: "bar",
        stack: "spend"
      }
    end)
    |> Kernel.++(projected_series(projected_days, dates))
  end

  # Days the period has not reached yet, at the rate it has run so far.
  # Its own muted series rather than another repository, because it is a
  # forecast and should not read as spend that happened.
  defp projected_series([], _dates), do: []

  defp projected_series(projected_days, dates) do
    per_day = Map.new(projected_days, &{&1.date, &1.total_ms})

    [
      %{
        color: "var:noora-chart-lines",
        data: Enum.map(dates, fn date -> [date, dollars(Map.get(per_day, date, 0))] end),
        name: dgettext("dashboard_usage", "Projected"),
        type: "bar",
        stack: "spend"
      }
    ]
  end

  def repository_label(nil), do: dgettext("dashboard_usage", "Unknown")
  def repository_label(""), do: dgettext("dashboard_usage", "Unknown")
  def repository_label(repository), do: repository

  # The chart has no currency formatter for its data, only its labels,
  # so values arrive already in dollars.
  defp dollars(total_ms) do
    total_ms |> Prepaid.on_demand_cost_for_milliseconds() |> Map.get(:amount) |> Kernel./(100) |> Float.round(2)
  end

  @doc """
  How much of this period's runner charge the account's prepaid credit
  would absorb, and what is left to pay.

  Prepaid credit is held at account level rather than per platform, so
  this is a whole-period figure rather than a line on any one receipt.
  It is an estimate: Stripe draws the grant down when it invoices, so
  what is shown here is what the current balance would cover if the
  period closed now.
  """
  def prepaid_coverage(nil, _breakdown), do: nil

  def prepaid_coverage(%{available: available}, %{billed: billed}) do
    covered = if Money.compare(available, billed) == -1, do: available, else: billed

    %{available: available, covered: covered, due: Money.subtract(billed, covered)}
  end

  @doc """
  What the account owes for the period: the usage charge less whatever
  its prepaid balance would cover today.

  This is the figure a customer reads first, so it has to be the money
  rather than the line item the money lands on. The receipt below the
  widget breaks the same number down into balance, drawdown and
  remainder.
  """
  def amount_due(%{billed: billed}, nil), do: billed
  def amount_due(_breakdown, %{due: due}), do: due

  @doc """
  The money a runner trial took off this row, or `nil` when it took
  none. A zero credit is a line that explains nothing, and an account
  that was never on a trial has no business being told about one.
  """
  def trial_credit(%{trial_covered: nil}), do: nil
  def trial_credit(%{trial_covered: %Money{amount: 0}}), do: nil
  def trial_credit(%{trial_covered: covered}), do: covered

  @doc """
  A credit, signed only when there is something to subtract. A bare
  "−0.00" reads as a rounding artefact rather than as nothing owed.
  """
  def credit_label(%Money{amount: 0}), do: money_label(Money.new(0, :USD))
  def credit_label(money), do: "−" <> money_label(money)

  def platform_shape(:macos), do: "6 vCPU / 14 GB"
  def platform_shape(:linux), do: "2 vCPU / 8 GB"
  def platform_shape(_other), do: ""

  @doc """
  The allowance expressed as the money it takes off the bill, so the
  receipt reads as a subtraction rather than as a bare minute count.
  """
  def included_credit_label(%{included_minutes: nil}), do: "—"

  def included_credit_label(%{gross: gross, trial_covered: trial_covered, billed: billed}) when not is_nil(gross) do
    # What a trial covered has a credit line of its own, so the allowance
    # only ever takes money off what was left billable after it. Reading
    # this off gross would subtract the trial twice.
    gross
    |> Money.subtract(trial_covered)
    |> Money.subtract(billed)
    |> credit_label()
  end

  def included_credit_label(_row), do: "—"

  @doc """
  Where the month lands if it carries on at this rate. A sentence
  rather than a column, because it is an extrapolation and should read
  like one.
  """
  def pace_label(%{projected_minutes: nil, previous_minutes: previous}) when previous > 0,
    do: dgettext("dashboard_usage", "Last period came to %{count} minutes.", count: CldrHelpers.format_number(previous))

  def pace_label(%{projected_minutes: nil}), do: nil

  def pace_label(%{minutes: minutes, projected_minutes: projected, previous_minutes: previous}) do
    pace =
      dgettext("dashboard_usage", "On track for about %{count} minutes this period.",
        count: CldrHelpers.format_number(projected)
      )

    case previous do
      0 when minutes > 0 ->
        pace <> " " <> dgettext("dashboard_usage", "Nothing ran last period.")

      0 ->
        pace

      _ ->
        pace <>
          " " <>
          dgettext("dashboard_usage", "Last period came to %{count}.", count: CldrHelpers.format_number(previous))
    end
  end

  def platform_label(:macos), do: dgettext("dashboard_usage", "macOS")
  def platform_label(:linux), do: dgettext("dashboard_usage", "Linux")
  def platform_label(other), do: to_string(other)

  @doc """
  Column heading carrying the period it covers, so the figures beneath
  it are not read as all-time.
  """
  def current_period_label(%{period_start: from, period_end: to}) do
    dgettext("dashboard_usage", "Current period %{from} – %{to}",
      from: Timex.format!(from, "{Mshort} {D}"),
      to: Timex.format!(to, "{Mshort} {D}")
    )
  end

  @doc """
  Money, or a dash for a platform with no agreed rate yet.
  """
  def money_label(nil), do: "—"
  def money_label(money), do: CldrHelpers.format_money(money)

  @doc """
  Chart options for the cache usage card's selected view: money for the
  charge, bytes for egress, and a plain count for requests.
  """
  def cache_chart_options(dates, view) do
    {formatter, value_format} =
      case view do
        "egress" -> {"fn:formatBytes", "fn:formatBytes"}
        "requests" -> {"fn:formatNumber", "fn:formatNumber"}
        "charge" -> {"fn:formatCurrency", "fn:formatCurrency"}
      end

    dates
    |> runner_chart_options()
    |> Map.merge(%{legend: chart_legend(), grid: %{left: 12, right: 16, top: 16, bottom: 40, containLabel: true}})
    |> Map.put(:tooltip, %{valueFormat: value_format})
    |> put_in([:yAxis, :axisLabel, :formatter], formatter)
  end

  @doc """
  Every date a usage pricing chart draws, spend and projection alike.
  """
  def usage_chart_dates(%{days: days, projected_days: projected_days}) do
    (days ++ projected_days)
    |> Enum.map(& &1.date)
    |> Enum.uniq()
    |> Enum.sort(Date)
  end

  @doc """
  The cache usage card's chart for the selected view, followed by the
  projection for the days the period has not reached yet. The charge is split
  by meter, and egress and requests by cache.
  """
  def cache_chart_series(%{charge_days: charge_days} = cache, "charge") do
    dates = usage_chart_dates(cache)

    [
      bar_series(
        dgettext("dashboard_usage", "Egress"),
        "primary",
        dates,
        Enum.filter(charge_days, &(&1.meter == :egress)),
        :dollars
      ),
      bar_series(
        dgettext("dashboard_usage", "Requests"),
        "secondary",
        dates,
        Enum.filter(charge_days, &(&1.meter == :requests)),
        :dollars
      )
    ] ++ projected_series(cache.projected_days, dates, :dollars)
  end

  def cache_chart_series(%{days: days} = cache, view) do
    field = if view == "egress", do: :bytes, else: :requests
    dates = usage_chart_dates(cache)

    days
    |> Enum.group_by(& &1.project)
    |> Enum.sort_by(fn {_project, rows} -> -Enum.sum(Enum.map(rows, &Map.fetch!(&1, field))) end)
    |> Enum.with_index()
    |> Enum.map(fn {{project, rows}, index} ->
      bar_series(
        project_label(project),
        Enum.at(@repository_colors, rem(index, length(@repository_colors))),
        dates,
        rows,
        field
      )
    end)
    |> Kernel.++(projected_series(cache.projected_days, dates, field))
  end

  @doc """
  The daily value of billable passing test cases, followed by the projection
  for the days the period has not reached yet.
  """
  def tests_chart_series(%{days: days, projected_days: projected_days} = tests) do
    dates = usage_chart_dates(tests)

    [bar_series(dgettext("dashboard_usage", "Passing test cases"), "primary", dates, days, :dollars)] ++
      projected_series(projected_days, dates, :dollars)
  end

  defp projected_series([], _dates, _field), do: []

  defp projected_series(projected_days, dates, field),
    do: [bar_series(dgettext("dashboard_usage", "Projected"), "lines", dates, projected_days, field)]

  defp bar_series(name, color, dates, rows, field) do
    %{
      color: "var:noora-chart-#{color}",
      data: bar_series_data(dates, rows, field),
      name: name,
      type: "bar",
      stack: "spend"
    }
  end

  defp bar_series_data(dates, rows, field) do
    per_day =
      rows
      |> Enum.group_by(& &1.date, &Map.fetch!(&1, field))
      |> Map.new(fn {date, values} -> {date, Enum.sum(values)} end)

    Enum.map(dates, fn date -> [date, chart_value(Map.get(per_day, date, 0), field)] end)
  end

  defp chart_value(value, :dollars), do: Float.round(value / 1, 2)
  defp chart_value(value, _field), do: round(value)

  def runner_usage?(%{minutes: minutes, by_repository: by_repository}), do: minutes > 0 or by_repository != []

  def cache_used?(%{egress: egress, requests: requests}), do: egress.quantity > 0 or requests.quantity > 0

  def tests_used?(tests), do: tests.passed + not_billed_test_cases(tests) > 0

  attr :title, :string, required: true
  attr :get_started_href, :string, required: true
  attr :rest, :global

  def usage_empty_state(assigns) do
    ~H"""
    <.empty_card_section title={@title} get_started_href={@get_started_href} {@rest}>
      <:image>
        <img
          src={~p"/images/empty_bar_chart_light.png"}
          data-theme="light"
          loading="lazy"
          decoding="async"
        />
        <img
          src={~p"/images/empty_bar_chart_dark.png"}
          data-theme="dark"
          loading="lazy"
          decoding="async"
        />
      </:image>
    </.empty_card_section>
    """
  end

  def egress_rate_label, do: "$0.35 " <> dgettext("dashboard_usage", "per GB")

  def request_rate_label,
    do: "$0.01 " <> dgettext("dashboard_usage", "per %{count}", count: CldrHelpers.format_number(1_000))

  def passing_test_case_rate_label, do: "$2 " <> dgettext("dashboard_usage", "per million")

  def project_label(nil), do: dgettext("dashboard_usage", "Unknown project")
  def project_label(project), do: project

  @doc """
  The heading of a usage pricing charge. Only an account with a subscription
  is billed, so every other account is shown an estimate.
  """
  def usage_charge_title(%{billed: nil}), do: dgettext("dashboard_usage", "Estimated")
  def usage_charge_title(_section), do: dgettext("dashboard_usage", "Billed")

  def usage_charge_description(%{billed: nil}),
    do: dgettext("dashboard_usage", "What this period comes to. There is no subscription to bill it to.")

  def usage_charge_description(_section), do: dgettext("dashboard_usage", "What you'll owe for this period")

  def usage_total_label(%{billed: nil}), do: dgettext("dashboard_usage", "Estimated for this period")
  def usage_total_label(_section), do: dgettext("dashboard_usage", "Billed this period")

  def not_billed_test_cases(%{failed: failed, skipped: skipped, on_runners: on_runners}),
    do: failed + skipped + on_runners

  def egress_pace_label(%{projected: nil}), do: nil

  def egress_pace_label(%{projected: projected}),
    do: dgettext("dashboard_usage", "On track for about %{size} this period.", size: format_bytes(projected))

  def requests_pace_label(%{projected: nil}), do: nil

  def requests_pace_label(%{projected: projected}),
    do:
      dgettext("dashboard_usage", "On track for about %{count} requests this period.",
        count: CldrHelpers.format_number(projected)
      )

  def tests_pace_label(%{projected: nil}), do: nil

  def tests_pace_label(%{projected: projected}),
    do:
      dgettext("dashboard_usage", "On track for about %{count} passing test cases this period.",
        count: CldrHelpers.format_number(projected)
      )

  def region_label(""), do: dgettext("dashboard_usage", "Unknown")
  def region_label(nil), do: dgettext("dashboard_usage", "Unknown")
  def region_label(region) when is_binary(region), do: region

  def format_bytes(value), do: ByteFormatter.format_bytes(value || 0)
  def format_count(value) when is_integer(value), do: CldrHelpers.format_number(value)
  def format_count(_), do: CldrHelpers.format_number(0)

  def empty_label, do: dgettext("dashboard_usage", "No cache traffic in this window yet")
end
