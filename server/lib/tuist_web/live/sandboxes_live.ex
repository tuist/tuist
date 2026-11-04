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
  @recent_count 5
  @widgets ["created", "session_duration", "setup", "time_to_start"]

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    ensure_available!(user, account)

    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     assign(socket,
       head_title: "#{dgettext("dashboard_sandboxes", "Sandboxes")} · #{account.name} · Tuist",
       can_manage_integrations: Authorization.authorize(:account_update, user, account) == :ok
     )}
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
      usage: Concurrency.usage(account.id),
      amp_integration: account.id |> AmpIntegrations.get() |> AmpIntegrations.public_status()
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

  # ----- Presentation shared with SandboxLive and SandboxInstancesLive -----

  attr :id, :string, required: true
  attr :sandboxes, :list, required: true
  attr :account, :map, required: true

  def sandboxes_table(assigns) do
    ~H"""
    <.table
      id={@id}
      rows={@sandboxes}
      row_key={fn sandbox -> "sandbox-#{sandbox.id}" end}
      row_navigate={fn sandbox -> ~p"/#{@account.name}/sandboxes/#{sandbox.id}" end}
    >
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Name")}>
        <.text_cell label={display_name(sandbox)} sublabel={short_id(sandbox.id)} />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Source")}>
        <.badge_cell label={source_label(sandbox)} color="neutral" style="light-fill" />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Status")}>
        <% status = status(sandbox) %>
        <.status_badge_cell label={status.label} status={status.status} />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Resources")}>
        <.text_cell label={resources(sandbox)} />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Last active")}>
        <.text_cell
          label={relative_time(last_active_at(sandbox))}
          title={time(last_active_at(sandbox))}
        />
      </:col>
      <:col :let={sandbox} label={dgettext("dashboard_sandboxes", "Created")}>
        <.text_cell label={relative_time(sandbox.inserted_at)} title={time(sandbox.inserted_at)} />
      </:col>
      <:empty_state>
        <.table_empty_state
          icon="devices_code"
          title={dgettext("dashboard_sandboxes", "No sandboxes with this status")}
          subtitle={dgettext("dashboard_sandboxes", "Choose a different status to see more.")}
        />
      </:empty_state>
    </.table>
    """
  end

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
