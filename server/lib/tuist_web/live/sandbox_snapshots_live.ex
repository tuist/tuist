defmodule TuistWeb.SandboxSnapshotsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.SandboxesLive, only: [gigabytes: 1, relative_time: 1, short_id: 1, time: 1]
  import TuistWeb.SandboxLive, only: [snapshot_status: 1]

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Sandboxes.DiskSnapshots
  alias TuistWeb.SandboxesLive

  @refresh_interval 15_000

  @impl true
  def mount(_params, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    SandboxesLive.ensure_available!(user, account)

    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     socket
     |> assign(
       head_title: "#{dgettext("dashboard_sandboxes", "Snapshots")} · #{account.name} · Tuist",
       can_manage: Authorization.authorize(:sandboxes_update, user, account) == :ok,
       retention_hours: DiskSnapshots.unused_retention_hours(),
       pending_delete: nil,
       deleting: false
     )
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load(socket)}
  end

  @impl true
  def handle_event("request_delete", %{"id" => id}, %{assigns: %{can_manage: true}} = socket) do
    if DiskSnapshots.get(socket.assigns.selected_account.id, id) do
      {:noreply, socket |> assign(:pending_delete, id) |> push_event("open-modal", %{id: "snapshot-confirm-delete"})}
    else
      {:noreply, load(socket)}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, socket |> assign(:pending_delete, nil) |> push_event("close-modal", %{id: "snapshot-confirm-delete"})}
  end

  def handle_event("delete", _params, %{assigns: %{pending_delete: id, deleting: false}} = socket) when is_binary(id) do
    %{selected_account: account, current_user: user} = socket.assigns
    socket = push_event(socket, "close-modal", %{id: "snapshot-confirm-delete"})

    with true <- FeatureFlags.sandboxes_enabled?(account),
         :ok <- Authorization.authorize(:sandboxes_update, user, account),
         snapshot when not is_nil(snapshot) <- DiskSnapshots.get(account.id, id) do
      {:noreply,
       socket
       |> assign(deleting: true, pending_delete: nil)
       |> start_async(:delete, fn -> DiskSnapshots.delete(snapshot) end)}
    else
      _ -> {:noreply, socket |> assign(:pending_delete, nil) |> load()}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:delete, {:ok, :ok}, socket) do
    {:noreply,
     socket
     |> assign(:deleting, false)
     |> put_flash(:info, dgettext("dashboard_sandboxes", "Snapshot deleted."))
     |> load()}
  end

  def handle_async(:delete, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:deleting, false)
     |> put_flash(:error, dgettext("dashboard_sandboxes", "Could not delete the snapshot. Please retry."))
     |> load()}
  end

  defp load(socket) do
    assign(socket, :snapshots, DiskSnapshots.list(socket.assigns.selected_account.id))
  end

  def expires(snapshot) do
    case DiskSnapshots.expires_at(snapshot) do
      nil -> "—"
      expires_at -> Timex.from_now(expires_at)
    end
  end
end
