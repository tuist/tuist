defmodule TuistWeb.SandboxesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.Skeleton
  import TuistWeb.EmptyState
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Analytics
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @refresh_interval 5_000
  @recent_count 5
  @widgets ["created", "session_duration", "setup", "time_to_start"]

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    ensure_available!(user, account)

    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok, assign(socket, head_title: "#{dgettext("dashboard_sandboxes", "Sandboxes")} · #{account.name} · Tuist")}
  end

  @impl true
  def handle_params(params, uri, %{assigns: %{selected_account: account}} = socket) do
    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    {:noreply,
     socket
     |> assign(
       uri: URI.parse(uri),
       analytics_preset: preset,
       analytics_period: period,
       analytics_trend_label: trend_label(preset),
       analytics_selected_widget: if(params["widget"] in @widgets, do: params["widget"], else: "created"),
       session_duration_percentile: params["session-duration"] || "avg",
       setup_percentile: params["setup"] || "p50",
       time_to_start_percentile: params["time-to-start"] || "p50"
     )
     |> load()
     |> assign_async(:analytics, fn ->
       {:ok, %{analytics: Analytics.overview(account.id, start_datetime: start_datetime, end_datetime: end_datetime)}}
     end)}
  end

  @impl true
  def handle_event("select_widget", %{"widget" => widget}, socket) do
    {:noreply, patch_with_param(socket, "widget", widget)}
  end

  def handle_event("select_session_duration_percentile", %{"type" => type}, socket) do
    {:noreply, patch_with_param(socket, "session-duration", type)}
  end

  def handle_event("select_setup_percentile", %{"type" => type}, socket) do
    {:noreply, patch_with_param(socket, "setup", type)}
  end

  def handle_event("select_time_to_start_percentile", %{"type" => type}, socket) do
    {:noreply, patch_with_param(socket, "time-to-start", type)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: "/#{socket.assigns.selected_account.name}/sandboxes?#{query}")}
  end

  defp patch_with_param(socket, key, value) do
    query = Query.put(socket.assigns.uri.query, key, value)
    push_patch(socket, to: "/#{socket.assigns.selected_account.name}/sandboxes?#{query}")
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load(socket)}
  end

  defp load(%{assigns: %{selected_account: account}} = socket) do
    counts = Sandboxes.count_sandboxes_by_state(account)

    assign(socket,
      sandboxes: Sandboxes.list_sandboxes(account, limit: @recent_count),
      counts: counts,
      total: counts |> Map.values() |> Enum.sum(),
      usage: Map.put(Concurrency.usage(account.id), :disk_mb, Concurrency.disk_usage_mb(account.id))
    )
  end

  @doc """
  Raises `NotFoundError` unless the account has sandboxes and the user may
  see them, so the pages do not exist for anyone else.
  """
  def ensure_available!(user, account) do
    if !(FeatureFlags.sandboxes_enabled?(account) and Authorization.authorize(:sandboxes_read, user, account) == :ok) do
      raise NotFoundError
    end
  end

  defp trend_label("last-24-hours"), do: dgettext("dashboard_sandboxes", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_sandboxes", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_sandboxes", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_sandboxes", "since last period")
  defp trend_label(_), do: dgettext("dashboard_sandboxes", "since last month")

  @doc """
  Percentile lines for a duration that not every bucket has, such as setup,
  joined across the buckets without one.
  """
  def gapped_duration_series(stats),
    do: Enum.map(TuistWeb.RunnersLive.duration_chart_series(stats), &Map.put(&1, :connectNulls, true))

  def count_series(%{dates: dates, values: values}, name) do
    [
      %{
        color: "var:noora-chart-primary",
        data: dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1),
        name: name,
        type: "line",
        smooth: 0.1,
        symbol: "none"
      }
    ]
  end

  @doc """
  The peak usage charts, each against the account's limit, with what is in
  use right now.
  """
  def concurrency_charts(concurrency, usage, account) do
    [
      %{
        id: "vcpus",
        title: dgettext("dashboard_sandboxes", "vCPUs"),
        subtitle:
          dgettext("dashboard_sandboxes", "%{count} of %{limit} in use now",
            count: usage.vcpus,
            limit: account.sandbox_vcpus_limit
          ),
        values: concurrency.vcpus,
        limit: account.sandbox_vcpus_limit,
        usage_label: dgettext("dashboard_sandboxes", "Peak vCPUs")
      },
      %{
        id: "memory",
        title: dgettext("dashboard_sandboxes", "Memory"),
        subtitle:
          dgettext("dashboard_sandboxes", "%{count} of %{limit} in use now",
            count: gigabytes(usage.memory_mb / 1024),
            limit: gigabytes(account.sandbox_memory_gb_limit)
          ),
        values: concurrency.memory_gb,
        limit: account.sandbox_memory_gb_limit,
        usage_label: dgettext("dashboard_sandboxes", "Peak memory (GB)")
      },
      %{
        id: "disk",
        title: dgettext("dashboard_sandboxes", "Disk"),
        subtitle:
          dgettext("dashboard_sandboxes", "%{count} of %{limit} on nodes now",
            count: gigabytes(usage.disk_mb / 1024),
            limit: gigabytes(account.sandbox_disk_gb_limit)
          ),
        values: concurrency.disk_gb,
        limit: account.sandbox_disk_gb_limit,
        usage_label: dgettext("dashboard_sandboxes", "Peak disk (GB)")
      }
    ]
  end

  def concurrency_chart_series(values, limit, usage_label) do
    [
      %{
        data:
          Enum.map(
            values,
            &if(&1 >= limit, do: %{value: &1, itemStyle: %{color: "var:noora-chart-destructive"}}, else: &1)
          ),
        itemStyle: %{color: "var:noora-chart-primary"},
        name: usage_label,
        type: "bar",
        barMaxWidth: 18
      },
      %{
        data: List.duplicate(limit, length(values)),
        name: dgettext("dashboard_sandboxes", "Limit"),
        type: "line",
        symbol: "none",
        silent: true,
        itemStyle: %{color: "var:noora-chart-destructive"},
        lineStyle: %{color: "var:noora-chart-destructive", type: "dashed", width: 1.5}
      }
    ]
  end

  def concurrency_chart_options(analytics_preset) do
    hourly? = analytics_preset == "last-24-hours"

    %{
      grid: %{left: 34, right: 24, top: 8, bottom: 36},
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
        itemWidth: 10,
        itemHeight: 4
      },
      xAxis: %{
        boundaryGap: true,
        axisLabel: %{
          color: "var:noora-surface-label-secondary",
          formatter: if(hourly?, do: "fn:toLocaleDateHour", else: "fn:toLocaleDate"),
          hideOverlap: true,
          padding: [8, 0, 0, 0]
        }
      },
      yAxis: %{
        splitNumber: 4,
        splitLine: %{lineStyle: %{color: "var:noora-chart-lines"}},
        axisLabel: %{color: "var:noora-surface-label-secondary"}
      },
      tooltip: if(hourly?, do: %{dateFormat: "hour"}, else: %{})
    }
  end

  def empty_state_light_background(assigns) do
    ~H"""
    <svg width="984" height="617" viewBox="0 0 984 617" fill="none" xmlns="http://www.w3.org/2000/svg">
      <mask
        id="mask0_8530_106253"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="984"
        height="617"
      >
        <rect width="984" height="617" fill="url(#paint0_radial_8530_106253)" fill-opacity="0.4" />
        <rect width="984" height="617" fill="url(#paint1_radial_8530_106253)" fill-opacity="0.4" />
        <rect width="984" height="617" fill="url(#paint2_radial_8530_106253)" fill-opacity="0.4" />
        <rect width="984" height="617" fill="url(#paint3_radial_8530_106253)" fill-opacity="0.4" />
      </mask>
      <g mask="url(#mask0_8530_106253)">
        <rect x="142.859" y="395.008" width="700.065" height="222.014" fill="#EFF0F1" />
        <rect
          x="258.773"
          y="145.32"
          width="467.671"
          height="83.039"
          fill="url(#paint4_linear_8530_106253)"
        />
        <path
          d="M171.688 203.448L258.763 145.32V232.209L171.688 290.639V203.448Z"
          fill="url(#paint5_linear_8530_106253)"
        />
        <path
          d="M808.328 205.062L726.442 145.32V234.622L808.328 294.675V205.062Z"
          fill="url(#paint6_linear_8530_106253)"
        />
        <g filter="url(#filter0_i_8530_106253)">
          <path d="M1 0L136.841 4.75512L258.767 145.923L173.71 202.408L1 0Z" fill="#EFF0F1" />
        </g>
        <g filter="url(#filter1_i_8530_106253)">
          <path
            d="M984.203 0L848.362 4.75512L726.436 145.923L800.249 204.138L984.203 0Z"
            fill="#EFF0F1"
          />
        </g>
        <g filter="url(#filter2_ddddi_8530_106253)">
          <path
            d="M169.586 205.356C170.697 202.859 173.174 201.25 175.908 201.25H803.383C806.053 201.25 808.484 202.785 809.631 205.195L895.297 385.113C897.483 389.705 894.135 395.008 889.049 395.008H95.8412C90.8321 395.008 87.4825 389.851 89.519 385.274L169.586 205.356Z"
            fill="#EFF0F1"
          />
        </g>
      </g>
      <defs>
        <filter
          id="filter0_i_8530_106253"
          x="1"
          y="-1.72998"
          width="257.766"
          height="204.136"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-1.72998" />
          <feGaussianBlur stdDeviation="2.30664" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_8530_106253" />
        </filter>
        <filter
          id="filter1_i_8530_106253"
          x="726.438"
          y="-1.72998"
          width="257.766"
          height="205.871"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-1.72998" />
          <feGaussianBlur stdDeviation="2.30664" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_8530_106253" />
        </filter>
        <filter
          id="filter2_ddddi_8530_106253"
          x="-3.35154"
          y="183.95"
          width="991.594"
          height="533.987"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="14.4165" />
          <feGaussianBlur stdDeviation="15.8582" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.1 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_8530_106253" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="57.666" />
          <feGaussianBlur stdDeviation="28.833" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.09 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_8530_106253"
            result="effect2_dropShadow_8530_106253"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="129.749" />
          <feGaussianBlur stdDeviation="38.9246" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.05 0" />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_8530_106253"
            result="effect3_dropShadow_8530_106253"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="230.664" />
          <feGaussianBlur stdDeviation="46.1328" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.01 0" />
          <feBlend
            mode="normal"
            in2="effect3_dropShadow_8530_106253"
            result="effect4_dropShadow_8530_106253"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect4_dropShadow_8530_106253"
            result="shape"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-1.15332" />
          <feGaussianBlur stdDeviation="1.15332" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect5_innerShadow_8530_106253" />
        </filter>
        <radialGradient
          id="paint0_radial_8530_106253"
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(274.672 -187.757 299.437 221.093 733.845 172.406)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#E51C01" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint1_radial_8530_106253"
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(-341.99 250.638 -399.721 -275.28 341.99 370.495)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#FFC300" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint2_radial_8530_106253"
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(358.196 208.422 -332.394 288.324 602.534 371.086)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#F44277" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint3_radial_8530_106253"
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(-282.152 -244.733 390.304 -227.114 282.152 260.38)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#8366FF" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <linearGradient
          id="paint4_linear_8530_106253"
          x1="492.609"
          y1="228.359"
          x2="492.609"
          y2="145.32"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#D9D9D9" />
          <stop offset="1" stop-color="#ABABAB" />
        </linearGradient>
        <linearGradient
          id="paint5_linear_8530_106253"
          x1="215.225"
          y1="290.639"
          x2="215.225"
          y2="145.32"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#D9D9D9" />
          <stop offset="1" stop-color="#ABABAB" />
        </linearGradient>
        <linearGradient
          id="paint6_linear_8530_106253"
          x1="767.385"
          y1="294.675"
          x2="767.385"
          y2="145.32"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#D9D9D9" />
          <stop offset="1" stop-color="#ABABAB" />
        </linearGradient>
      </defs>
    </svg>
    """
  end

  def empty_state_dark_background(assigns) do
    ~H"""
    <svg width="984" height="617" viewBox="0 0 984 617" fill="none" xmlns="http://www.w3.org/2000/svg">
      <mask
        id="mask0_8530_106330"
        style="mask-type:alpha"
        maskUnits="userSpaceOnUse"
        x="0"
        y="0"
        width="984"
        height="617"
      >
        <rect width="984" height="617" fill="url(#paint0_radial_8530_106330)" fill-opacity="0.4" />
        <rect width="984" height="617" fill="url(#paint1_radial_8530_106330)" fill-opacity="0.4" />
        <rect width="984" height="617" fill="url(#paint2_radial_8530_106330)" fill-opacity="0.4" />
        <rect width="984" height="617" fill="url(#paint3_radial_8530_106330)" fill-opacity="0.4" />
      </mask>
      <g mask="url(#mask0_8530_106330)">
        <rect x="141.859" y="395.008" width="700.065" height="222.014" fill="#2E2E2E" />
        <rect
          x="257.773"
          y="145.32"
          width="467.671"
          height="83.039"
          fill="url(#paint4_linear_8530_106330)"
        />
        <path
          d="M170.688 203.448L257.763 145.32V232.209L170.688 290.639V203.448Z"
          fill="url(#paint5_linear_8530_106330)"
        />
        <path
          d="M807.328 205.062L725.442 145.32V234.622L807.328 294.675V205.062Z"
          fill="url(#paint6_linear_8530_106330)"
        />
        <g filter="url(#filter0_i_8530_106330)">
          <path d="M0 0L135.841 4.75512L257.767 145.923L172.71 202.408L0 0Z" fill="#2E2E2E" />
        </g>
        <g filter="url(#filter1_i_8530_106330)">
          <path
            d="M983.203 0L847.362 4.75512L725.436 145.923L799.249 204.138L983.203 0Z"
            fill="#2E2E2E"
          />
        </g>
        <g filter="url(#filter2_ddddi_8530_106330)">
          <path
            d="M168.586 205.356C169.697 202.859 172.174 201.25 174.908 201.25H802.383C805.053 201.25 807.484 202.785 808.631 205.195L894.297 385.113C896.483 389.705 893.135 395.008 888.049 395.008H94.8412C89.8321 395.008 86.4825 389.851 88.519 385.274L168.586 205.356Z"
            fill="#2E2E2E"
          />
        </g>
      </g>
      <defs>
        <filter
          id="filter0_i_8530_106330"
          x="0"
          y="-1.72998"
          width="257.766"
          height="204.136"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-1.72998" />
          <feGaussianBlur stdDeviation="2.30664" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_8530_106330" />
        </filter>
        <filter
          id="filter1_i_8530_106330"
          x="725.438"
          y="-1.72998"
          width="257.766"
          height="205.871"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feBlend mode="normal" in="SourceGraphic" in2="BackgroundImageFix" result="shape" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-1.72998" />
          <feGaussianBlur stdDeviation="2.30664" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect1_innerShadow_8530_106330" />
        </filter>
        <filter
          id="filter2_ddddi_8530_106330"
          x="-4.35154"
          y="183.95"
          width="991.594"
          height="533.987"
          filterUnits="userSpaceOnUse"
          color-interpolation-filters="sRGB"
        >
          <feFlood flood-opacity="0" result="BackgroundImageFix" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="14.4165" />
          <feGaussianBlur stdDeviation="15.8582" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.1 0" />
          <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_8530_106330" />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="57.666" />
          <feGaussianBlur stdDeviation="28.833" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.09 0" />
          <feBlend
            mode="normal"
            in2="effect1_dropShadow_8530_106330"
            result="effect2_dropShadow_8530_106330"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="129.749" />
          <feGaussianBlur stdDeviation="38.9246" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.05 0" />
          <feBlend
            mode="normal"
            in2="effect2_dropShadow_8530_106330"
            result="effect3_dropShadow_8530_106330"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="230.664" />
          <feGaussianBlur stdDeviation="46.1328" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.01 0" />
          <feBlend
            mode="normal"
            in2="effect3_dropShadow_8530_106330"
            result="effect4_dropShadow_8530_106330"
          />
          <feBlend
            mode="normal"
            in="SourceGraphic"
            in2="effect4_dropShadow_8530_106330"
            result="shape"
          />
          <feColorMatrix
            in="SourceAlpha"
            type="matrix"
            values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0"
            result="hardAlpha"
          />
          <feOffset dy="-1.15332" />
          <feGaussianBlur stdDeviation="1.15332" />
          <feComposite in2="hardAlpha" operator="arithmetic" k2="-1" k3="1" />
          <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0" />
          <feBlend mode="normal" in2="shape" result="effect5_innerShadow_8530_106330" />
        </filter>
        <radialGradient
          id="paint0_radial_8530_106330"
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(274.672 -187.757 299.437 221.093 733.845 172.406)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#E51C01" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint1_radial_8530_106330"
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(-341.99 250.638 -399.721 -275.28 341.99 370.495)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#FFC300" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint2_radial_8530_106330"
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(358.196 208.422 -332.394 288.324 602.534 371.086)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#F44277" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <radialGradient
          id="paint3_radial_8530_106330"
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(-282.152 -244.733 390.304 -227.114 282.152 260.38)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#8366FF" />
          <stop offset="1" stop-opacity="0" />
        </radialGradient>
        <linearGradient
          id="paint4_linear_8530_106330"
          x1="491.609"
          y1="228.359"
          x2="491.609"
          y2="145.32"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#222222" />
          <stop offset="1" stop-color="#0E0E0E" />
        </linearGradient>
        <linearGradient
          id="paint5_linear_8530_106330"
          x1="214.225"
          y1="290.639"
          x2="214.225"
          y2="145.32"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#222222" />
          <stop offset="1" stop-color="#0E0E0E" />
        </linearGradient>
        <linearGradient
          id="paint6_linear_8530_106330"
          x1="766.385"
          y1="294.675"
          x2="766.385"
          y2="145.32"
          gradientUnits="userSpaceOnUse"
        >
          <stop stop-color="#222222" />
          <stop offset="1" stop-color="#0E0E0E" />
        </linearGradient>
      </defs>
    </svg>
    """
  end

  # ----- Presentation shared with SandboxLive and SandboxInstancesLive -----

  attr :flash, :map, required: true

  @doc "The page's info and error flashes, which the app layout does not render."
  def flash_alerts(assigns) do
    ~H"""
    <.alert
      :for={{kind, status, message} <- flash_entries(@flash)}
      id={"sandbox-flash-#{kind}"}
      status={status}
      type="secondary"
      size="small"
      title={message}
    />
    """
  end

  defp flash_entries(flash) do
    for {kind, status} <- [info: "information", error: "error"],
        message <- [Phoenix.Flash.get(flash, kind)],
        message,
        do: {kind, status, message}
  end

  attr :creator, :map, required: true

  def creator_badge_cell(assigns) do
    ~H"""
    <.badge_cell
      label={@creator.name || dgettext("dashboard", "Unknown")}
      icon={
        case @creator.source do
          :matched -> "user"
          :reported -> "device_laptop"
          _ -> nil
        end
      }
      color={if @creator.source == :matched, do: "primary", else: "neutral"}
      style="light-fill"
      data-actor-source={@creator.source}
    />
    """
  end

  attr :id, :string, required: true
  attr :sandboxes, :list, required: true
  attr :account, :map, required: true
  attr :sort_patch, :any, default: nil, doc: "A function from a column to its sort patch; makes columns sortable."
  attr :sort_by, :string, default: nil
  attr :sort_order, :string, default: nil

  def sandboxes_table(assigns) do
    ~H"""
    <.table
      id={@id}
      rows={@sandboxes}
      row_key={fn sandbox -> "sandbox-#{sandbox.id}" end}
      row_navigate={fn sandbox -> ~p"/#{@account.name}/sandboxes/#{sandbox.id}" end}
    >
      <:col
        :let={sandbox}
        label={dgettext("dashboard_sandboxes", "Instance")}
        patch={@sort_patch && @sort_patch.("name")}
        sort_order={@sort_by == "name" && @sort_order}
      >
        <.text_cell label={compact_id(display_name(sandbox))} title={display_name(sandbox)} />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Status")}>
        <% status = status(sandbox) %>
        <.badge_cell label={status.label} color={status.color} style="light-fill" />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Created by")}>
        <.creator_badge_cell creator={sandbox.creator_actor} />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "vCPUs")}>
        <.text_cell label={to_string(sandbox.vcpus)} />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Memory")}>
        <.text_cell label={gigabytes(sandbox.memory_mb / 1024)} />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Disk")}>
        <.text_cell label={gigabytes(sandbox.workspace_gb)} />
      </:col>
      <:col
        :let={sandbox}
        label={dgettext("dashboard_sandboxes", "Last active")}
        patch={@sort_patch && @sort_patch.("last_active")}
        sort_order={@sort_by == "last_active" && @sort_order}
      >
        <.text_cell
          label={relative_time(last_active_at(sandbox))}
          title={time(last_active_at(sandbox))}
        />
      </:col>
      <:col
        :let={sandbox}
        label={dgettext("dashboard_sandboxes", "Created")}
        patch={@sort_patch && @sort_patch.("created")}
        sort_order={@sort_by == "created" && @sort_order}
      >
        <.text_cell label={relative_time(sandbox.inserted_at)} title={time(sandbox.inserted_at)} />
      </:col>
      <:empty_state>
        <.table_empty_state
          icon="box_model_2"
          title={dgettext("dashboard_sandboxes", "No sandboxes found")}
          subtitle={dgettext("dashboard_sandboxes", "Try a different search or filter.")}
        />
      </:empty_state>
    </.table>
    """
  end

  def display_name(%Sandbox{amp_orb_id: orb_id}) when is_binary(orb_id), do: orb_id
  def display_name(%Sandbox{anthropic_session_id: session_id}) when is_binary(session_id), do: session_id
  def display_name(%Sandbox{id: id}), do: id

  defp compact_id(id) do
    if String.length(id) > 24, do: String.slice(id, 0, 8) <> "…" <> String.slice(id, -8, 8), else: id
  end

  def status(%Sandbox{state: :running, residency_work_id: work_id}) when is_binary(work_id),
    do: %{label: dgettext("dashboard_sandboxes", "Active"), color: "success"}

  def status(%Sandbox{state: :running}), do: %{label: dgettext("dashboard_sandboxes", "Idle"), color: "warning"}
  def status(%Sandbox{state: :creating}), do: %{label: dgettext("dashboard_sandboxes", "Starting"), color: "information"}
  def status(%Sandbox{state: :resuming}), do: %{label: dgettext("dashboard_sandboxes", "Resuming"), color: "information"}
  def status(%Sandbox{state: :paused}), do: %{label: dgettext("dashboard_sandboxes", "Paused"), color: "neutral"}
  def status(%Sandbox{state: :archived}), do: %{label: dgettext("dashboard_sandboxes", "Archived"), color: "neutral"}
  def status(%Sandbox{state: :error}), do: %{label: dgettext("dashboard_sandboxes", "Failed"), color: "destructive"}
  def status(%Sandbox{state: :deleted}), do: %{label: dgettext("dashboard_sandboxes", "Deleting"), color: "neutral"}

  def gigabytes(value) when is_float(value) do
    if value == Float.round(value), do: gigabytes(trunc(value)), else: "#{Float.round(value, 1)} GB"
  end

  def gigabytes(value), do: "#{value} GB"

  def relative_time(nil), do: "—"
  def relative_time(value), do: DateFormatter.from_now(value)

  def time(nil), do: "—"
  def time(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")

  def last_active_at(%Sandbox{} = sandbox), do: sandbox.last_active_at || sandbox.inserted_at
end
