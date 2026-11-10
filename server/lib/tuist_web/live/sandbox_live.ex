defmodule TuistWeb.SandboxLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.SandboxesLive,
    only: [
      display_name: 1,
      flash_alerts: 1,
      gigabytes: 1,
      last_active_at: 1,
      relative_time: 1,
      status: 1,
      time: 1
    ]

  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Sandbox
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.SandboxesLive

  @refresh_interval 5_000

  @impl true
  def mount(%{"sandbox_id" => id}, _session, %{assigns: %{selected_account: account, current_user: user}} = socket) do
    SandboxesLive.ensure_available!(user, account)

    sandbox =
      case Sandboxes.get_sandbox(account, id) do
        {:ok, sandbox} -> sandbox
        {:error, :not_found} -> raise NotFoundError
      end

    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_interval)

    {:ok,
     socket
     |> assign(
       head_title: "#{display_name(sandbox)} · #{dgettext("dashboard_sandboxes", "Sandboxes")} · #{account.name} · Tuist",
       can_manage: Authorization.authorize(:sandboxes_update, user, account) == :ok,
       pending: nil
     )
     |> assign_sandbox(sandbox)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, refresh_sandbox(socket)}
  end

  @impl true
  def handle_event(action, _params, %{assigns: %{pending: nil}} = socket) when action in ["pause", "resume", "archive"] do
    run(socket, String.to_existing_atom(action))
  end

  def handle_event("request_delete", _params, %{assigns: %{can_manage: true}} = socket) do
    {:noreply, push_event(socket, "open-modal", %{id: "sandbox-confirm-delete"})}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "sandbox-confirm-delete"})}
  end

  def handle_event("delete", _params, %{assigns: %{pending: nil}} = socket) do
    run(push_event(socket, "close-modal", %{id: "sandbox-confirm-delete"}), :delete)
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:action, {:ok, {:delete, {:ok, _}}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, dgettext("dashboard_sandboxes", "Sandbox deleted."))
     |> push_navigate(to: ~p"/#{socket.assigns.selected_account.name}/sandboxes/instances")}
  end

  def handle_async(:action, {:ok, {:pause, {:ok, :skipped}}}, socket) do
    {:noreply,
     socket
     |> assign(:pending, nil)
     |> put_flash(:error, dgettext("dashboard_sandboxes", "The sandbox is busy with an agent task and was not paused."))
     |> refresh_sandbox()}
  end

  def handle_async(:action, {:ok, {:archive, :ok}}, socket) do
    {:noreply,
     socket
     |> assign(:pending, nil)
     |> put_flash(
       :info,
       dgettext("dashboard_sandboxes", "Archiving started. The sandbox shows as archived once its disks are uploaded.")
     )
     |> refresh_sandbox()}
  end

  def handle_async(:action, {:ok, {_action, {:ok, _}}}, socket) do
    {:noreply, socket |> assign(:pending, nil) |> refresh_sandbox()}
  end

  def handle_async(:action, {:ok, {_action, {:error, reason}}}, socket) do
    {:noreply, socket |> assign(:pending, nil) |> put_flash(:error, error_message(reason)) |> refresh_sandbox()}
  end

  def handle_async(:action, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:pending, nil)
     |> put_flash(:error, dgettext("dashboard_sandboxes", "Something went wrong. Please retry."))
     |> refresh_sandbox()}
  end

  # Node commands block for up to two minutes, so they run outside the
  # LiveView process. Authorization and the flag are rechecked on every
  # action, since an open page can outlive both.
  defp run(%{assigns: %{selected_account: account, current_user: user, sandbox: sandbox}} = socket, action) do
    if FeatureFlags.sandboxes_enabled?(account) and Authorization.authorize(:sandboxes_update, user, account) == :ok do
      {:noreply,
       socket
       |> assign(:pending, action)
       |> start_async(:action, fn -> {action, perform(action, sandbox)} end)}
    else
      {:noreply, socket}
    end
  end

  # An idle pause leaves a sandbox an agent is working in alone.
  defp perform(:pause, sandbox), do: Sandboxes.pause_idle(sandbox.id)
  defp perform(:resume, sandbox), do: Sandboxes.resume(sandbox)
  defp perform(:delete, sandbox), do: Sandboxes.delete(sandbox)
  defp perform(:archive, sandbox), do: Sandboxes.archive(sandbox)

  defp error_message({:invalid_state, _state}),
    do: dgettext("dashboard_sandboxes", "The sandbox changed state in the meantime. Please retry.")

  defp error_message(:sandbox_concurrency_limit),
    do: dgettext("dashboard_sandboxes", "Resuming would exceed this account's vCPU or memory limit.")

  defp error_message(reason) when reason in [:not_connected, :node_disconnected, :no_node, :timeout],
    do: dgettext("dashboard_sandboxes", "The machine running this sandbox is unreachable. Please retry.")

  defp error_message(_reason), do: dgettext("dashboard_sandboxes", "Something went wrong. Please retry.")

  defp refresh_sandbox(%{assigns: %{selected_account: account, sandbox: sandbox}} = socket) do
    case Sandboxes.get_sandbox(account, sandbox.id) do
      {:ok, sandbox} ->
        assign_sandbox(socket, sandbox)

      {:error, :not_found} ->
        socket
        |> put_flash(:info, dgettext("dashboard_sandboxes", "This sandbox was deleted."))
        |> push_navigate(to: ~p"/#{account.name}/sandboxes/instances")
    end
  end

  defp assign_sandbox(socket, sandbox) do
    assign(socket, sandbox: sandbox)
  end

  def can_pause?(%Sandbox{state: :running, residency_work_id: nil}), do: true
  def can_pause?(%Sandbox{}), do: false

  # Amp resumes and restores its Orbs itself when the next turn starts.
  def can_resume?(%Sandbox{state: state, amp_orb_id: nil}) when state in [:paused, :archived], do: true
  def can_resume?(%Sandbox{}), do: false

  def archiving?(%Sandbox{archive_upload_id: upload_id}), do: not is_nil(upload_id)

  def can_delete?(%Sandbox{state: state}), do: state in [:running, :paused, :archived, :error]
end
