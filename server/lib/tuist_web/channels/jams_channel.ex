defmodule TuistWeb.JamsChannel do
  @moduledoc false
  use Phoenix.Channel

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Jams
  alias TuistWeb.JamsSocket

  @poll_interval 10_000

  def join("threads:" <> scope, params, socket), do: join("jams:" <> scope, params, socket)

  def join("jams:" <> scope, _params, socket) do
    with [handle, id] <- String.split(scope, ":"),
         {:ok, target} <- target(id),
         %Account{} = account <- Accounts.get_account_by_handle(handle),
         {:ok, user} <- JamsSocket.authenticate(socket.assigns.bearer),
         :ok <- Jams.authorize(user, account) do
      # Subscribe before the authoritative read so a concurrent commit cannot
      # fall between the initial snapshot and subscription.
      Phoenix.PubSub.subscribe(Tuist.PubSub, Jams.topic(user.id, account.id))

      socket =
        socket
        |> assign(:app_user, user)
        |> assign(:account_handle, handle)
        |> assign(:account_id, account.id)
        |> assign(:target, target)

      case snapshot(socket) do
        {:ok, value} ->
          schedule_poll()
          {:ok, value, assign(socket, :snapshot, value)}

        _ ->
          {:error, %{reason: "not_found"}}
      end
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  def handle_info(:poll_snapshot, socket) do
    # Local PubSub is a latency optimization, not a cross-replica guarantee.
    # This read repairs lost notifications and revalidates grants within 10s.
    schedule_poll()
    refresh(socket)
  end

  def handle_info(:jams_changed, socket), do: refresh(socket)

  defp refresh(socket) do
    case snapshot(socket) do
      {:ok, value} ->
        if value != socket.assigns.snapshot, do: push(socket, "snapshot", value)
        {:noreply, assign(socket, :snapshot, value)}

      _ ->
        {:stop, :normal, socket}
    end
  end

  defp snapshot(socket) do
    with {:ok, user} <- JamsSocket.authenticate(socket.assigns.bearer),
         true <- user.id == socket.assigns.app_user.id,
         %Account{} = account <- Accounts.get_account_by_handle(socket.assigns.account_handle),
         true <- account.id == socket.assigns.account_id,
         :ok <- Jams.authorize(user, account),
         {:ok, value} <- Jams.snapshot(user, account, socket.assigns.target) do
      # Explicit allowlist: sockets carry invalidations, never conversation content.
      {:ok, Map.take(value, [:revision, :agent_status])}
    else
      _ -> {:error, :not_found}
    end
  end

  defp target("inbox"), do: {:ok, :inbox}
  defp target(id), do: Ecto.UUID.cast(id)
  defp schedule_poll, do: Process.send_after(self(), :poll_snapshot, @poll_interval)
end
