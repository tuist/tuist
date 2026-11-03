defmodule TuistWeb.SandboxesLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Widget

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpIntegrations
  alias Tuist.Sandboxes.Concurrency
  alias Tuist.Sandboxes.DiskSnapshots
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError

  @refresh_interval 5_000
  @filters ["all", "running", "paused", "error"]

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
  def handle_params(params, _uri, socket) do
    filter = if params["status"] in @filters, do: params["status"], else: "all"
    {:noreply, socket |> assign(:filter, filter) |> load()}
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
      snapshot_count: account.id |> DiskSnapshots.list() |> length(),
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
