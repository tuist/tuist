defmodule TuistWeb.SandboxesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpIntegrations
  alias Tuist.Sandboxes.Analytics
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Utilities.Query

  @refresh_interval 5_000
  @filters ["all", "running", "paused", "error"]
  @widgets ["created", "compute", "session_duration", "time_to_ready"]
  @time_to_ready_starts ["all", "template", "disk_snapshot", "archive"]

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    ensure_available!(user, account)

    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     assign(socket,
       head_title: "#{dgettext("dashboard_sandboxes", "Sandboxes")} · #{account.name} · Tuist",
       can_manage_integrations: Authorization.authorize(:account_update, user, account) == :ok,
       filter: "all"
     )}
  end

  @impl true
  def handle_params(params, uri, %{assigns: %{selected_account: account}} = socket) do
    filter = if params["status"] in @filters, do: params["status"], else: "all"

    %{preset: preset, period: {start_datetime, end_datetime} = period} =
      DatePicker.date_picker_params(params, "analytics")

    {:noreply,
     socket
     |> assign(
       uri: URI.parse(uri),
       filter: filter,
       analytics_preset: preset,
       analytics_period: period,
       analytics_trend_label: trend_label(preset),
       analytics_selected_widget: if(params["widget"] in @widgets, do: params["widget"], else: "created"),
       session_duration_percentile: params["session-duration"] || "avg",
       time_to_ready_percentile: params["time-to-ready"] || "p50",
       time_to_ready_start:
         if(params["time-to-ready-start"] in @time_to_ready_starts, do: params["time-to-ready-start"], else: "all")
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

  def handle_event("select_time_to_ready_percentile", %{"type" => type}, socket) do
    {:noreply, patch_with_param(socket, "time-to-ready", type)}
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
    push_patch(socket, to: status_patch(socket.assigns.selected_account, socket.assigns.uri, key, value))
  end

  def status_patch(account, uri, key \\ "status", value) do
    query =
      if key == "status" and value == "all", do: Query.drop(uri.query, "status"), else: Query.put(uri.query, key, value)

    "/#{account.name}/sandboxes?#{query}"
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load(socket)}
  end

  defp load(%{assigns: %{selected_account: account, filter: filter}} = socket) do
    counts = Sandboxes.count_sandboxes_by_state(account)

    assign(socket,
      sandboxes: Sandboxes.list_sandboxes(account, states: filter_states(filter)),
      counts: counts,
      total: counts |> Map.values() |> Enum.sum(),
      usage: Concurrency.usage(account.id),
      amp_integration: account.id |> AmpIntegrations.get() |> AmpIntegrations.public_status()
    )
  end

  defp filter_states("all"), do: nil
  defp filter_states("running"), do: [:creating, :resuming, :running]
  defp filter_states("paused"), do: [:paused, :archived]
  defp filter_states("error"), do: [:error]

  def filter_options do
    [
      {"all", dgettext("dashboard_sandboxes", "All")},
      {"running", dgettext("dashboard_sandboxes", "Running")},
      {"paused", dgettext("dashboard_sandboxes", "Paused")},
      {"error", dgettext("dashboard_sandboxes", "Failed")}
    ]
  end

  def filter_label(filter), do: filter_options() |> List.keyfind(filter, 0) |> elem(1)

  def filter_count(counts, "all"), do: counts |> Map.values() |> Enum.sum()

  def filter_count(counts, filter), do: filter |> filter_states() |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()

  @doc """
  Raises `NotFoundError` unless the account has sandboxes and the user may
  see them, so the pages do not exist for anyone else.
  """
  def ensure_available!(user, account) do
    if !(FeatureFlags.sandboxes_enabled?(account) and Authorization.authorize(:sandboxes_read, user, account) == :ok) do
      raise NotFoundError
    end
  end

  def running_count(counts), do: Enum.sum(for state <- [:creating, :resuming, :running], do: counts[state])

  defp trend_label("last-24-hours"), do: dgettext("dashboard_sandboxes", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_sandboxes", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_sandboxes", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_sandboxes", "since last period")
  defp trend_label(_), do: dgettext("dashboard_sandboxes", "since last month")

  def vcpu_hours(value) when value < 10, do: format_number(value, fractional_digits: 1)
  def vcpu_hours(value), do: format_number(value)

  @doc """
  The time-to-ready percentile lines for one way of starting. Lines join
  across buckets where no sandbox started that way.
  """
  def time_to_ready_series(stats),
    do: Enum.map(TuistWeb.RunnersLive.duration_chart_series(stats), &Map.put(&1, :connectNulls, true))

  def time_to_ready_starts, do: @time_to_ready_starts

  def boot_source_label("all"), do: dgettext("dashboard_sandboxes", "All")
  def boot_source_label("template"), do: dgettext("dashboard_sandboxes", "Cold boot and setup")
  def boot_source_label("disk_snapshot"), do: dgettext("dashboard_sandboxes", "From a project snapshot")
  def boot_source_label("archive"), do: dgettext("dashboard_sandboxes", "Restored from archive")

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
  def concurrency_charts(concurrency, counts, usage, account) do
    [
      %{
        id: "sandboxes",
        title: dgettext("dashboard_sandboxes", "Running sandboxes"),
        subtitle:
          dgettext("dashboard_sandboxes", "%{count} of %{limit} running now",
            count: running_count(counts),
            limit: Sandboxes.max_running_sandboxes_per_account()
          ),
        values: concurrency.sandboxes,
        limit: Sandboxes.max_running_sandboxes_per_account(),
        usage_label: dgettext("dashboard_sandboxes", "Peak sandboxes")
      },
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

  attr :account, :map, required: true
  attr :amp_integration, :map, default: nil
  attr :can_manage_integrations, :boolean, required: true

  def providers(assigns) do
    assigns = assign(assigns, :amp_connected, not is_nil(assigns.amp_integration) and assigns.amp_integration.enabled)

    ~H"""
    <div data-part="providers">
      <div data-part="provider" data-provider="amp">
        <div data-part="provider-icon"><.cube_send /></div>
        <div data-part="provider-text">
          <span data-part="provider-title">Amp</span>
          <span data-part="provider-subtitle">
            {dgettext("dashboard_sandboxes", "Self-hosted Orbs")}
          </span>
        </div>
        <div data-part="provider-action">
          <.status_badge
            :if={@amp_connected and @amp_integration.status == :error}
            status="warning"
            label={dgettext("dashboard_sandboxes", "Retrying")}
          />
          <.status_badge
            :if={@amp_connected and @amp_integration.status != :error}
            status="success"
            label={dgettext("dashboard_sandboxes", "Connected")}
          />
          <.button
            :if={not @amp_connected and @can_manage_integrations}
            variant="secondary"
            size="small"
            label={dgettext("dashboard_sandboxes", "Connect")}
            navigate={~p"/#{@account.name}/settings/integrations"}
          />
          <span :if={not @amp_connected and not @can_manage_integrations} data-part="provider-note">
            {dgettext("dashboard_sandboxes", "An admin can connect it")}
          </span>
        </div>
      </div>
      <div data-part="provider" data-provider="claude" data-disabled>
        <div data-part="provider-icon"><.brand_claude /></div>
        <div data-part="provider-text">
          <span data-part="provider-title">Claude</span>
          <span data-part="provider-subtitle">
            {dgettext("dashboard_sandboxes", "Claude Managed Agents")}
          </span>
        </div>
        <div data-part="provider-action">
          <.badge
            label={dgettext("dashboard_sandboxes", "Coming soon")}
            color="neutral"
            style="light-fill"
          />
        </div>
      </div>
      <div data-part="provider" data-provider="cli" data-disabled>
        <div data-part="provider-icon"><.brand_tuist /></div>
        <div data-part="provider-text">
          <span data-part="provider-title">{dgettext("dashboard_sandboxes", "Tuist CLI")}</span>
          <span data-part="provider-subtitle">
            {dgettext("dashboard_sandboxes", "Start sandboxes from your terminal")}
          </span>
        </div>
        <div data-part="provider-action">
          <.badge
            label={dgettext("dashboard_sandboxes", "Coming soon")}
            color="neutral"
            style="light-fill"
          />
        </div>
      </div>
    </div>
    """
  end

  # ----- Presentation shared with SandboxLive and SandboxSnapshotsLive -----

  def display_name(%Sandbox{amp_orb_id: orb_id}) when is_binary(orb_id), do: orb_id
  def display_name(%Sandbox{anthropic_session_id: session_id}) when is_binary(session_id), do: session_id
  def display_name(%Sandbox{id: id}), do: short_id(id)

  def short_id(id), do: String.slice(id, 0, 8)

  def source_label(%Sandbox{amp_orb_id: orb_id}) when is_binary(orb_id), do: dgettext("dashboard_sandboxes", "Amp Orb")

  def source_label(%Sandbox{agent_environment_id: id}) when not is_nil(id),
    do: dgettext("dashboard_sandboxes", "Claude Managed Agents")

  def source_label(%Sandbox{}), do: dgettext("dashboard_sandboxes", "API")

  def status(%Sandbox{state: :running, residency_work_id: work_id}) when is_binary(work_id),
    do: %{label: dgettext("dashboard_sandboxes", "Active"), status: "success"}

  def status(%Sandbox{state: :running}), do: %{label: dgettext("dashboard_sandboxes", "Idle"), status: "attention"}
  def status(%Sandbox{state: :creating}), do: %{label: dgettext("dashboard_sandboxes", "Starting"), status: "in_progress"}
  def status(%Sandbox{state: :resuming}), do: %{label: dgettext("dashboard_sandboxes", "Resuming"), status: "in_progress"}
  def status(%Sandbox{state: :paused}), do: %{label: dgettext("dashboard_sandboxes", "Paused"), status: "disabled"}
  def status(%Sandbox{state: :archived}), do: %{label: dgettext("dashboard_sandboxes", "Archived"), status: "disabled"}
  def status(%Sandbox{state: :error}), do: %{label: dgettext("dashboard_sandboxes", "Failed"), status: "error"}
  def status(%Sandbox{state: :deleted}), do: %{label: dgettext("dashboard_sandboxes", "Deleting"), status: "disabled"}

  def resources(%Sandbox{} = sandbox) do
    dgettext("dashboard_sandboxes", "%{vcpus} vCPU · %{memory} RAM · %{disk} disk",
      vcpus: sandbox.vcpus,
      memory: gigabytes(sandbox.memory_mb / 1024),
      disk: gigabytes(sandbox.workspace_gb)
    )
  end

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
