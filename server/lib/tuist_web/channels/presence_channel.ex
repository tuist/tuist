defmodule TuistWeb.PresenceChannel do
  @moduledoc """
  An organization's presence for Luft: joining `presence:<handle>`
  tracks the user as connected, and pushes `presence_state` then
  `presence_diff` with every member connected anywhere in the cluster.
  Keys are user IDs; each connection's meta carries the user's handle.
  """
  use Phoenix.Channel

  alias Phoenix.Socket.Broadcast
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Halls
  alias Tuist.Halls.Presence
  alias TuistWeb.ThreadsSocket

  # Revalidates the bearer, flags and membership, so someone removed from the
  # organization stops seeing and being seen within this long.
  @recheck_interval 30_000

  def join("presence:" <> handle, _params, socket) do
    with %Account{} = account <- Accounts.get_account_by_handle(handle),
         {:ok, user} <- ThreadsSocket.authenticate(socket.assigns.bearer),
         :ok <- Halls.authorize(user, account) do
      # Presence is tracked on an ID topic so a rename never splits it, and
      # this process subscribes to it to relay the diffs to the client.
      Phoenix.PubSub.subscribe(Tuist.PubSub, Presence.topic(account))
      send(self(), :after_join)
      Process.send_after(self(), :recheck, @recheck_interval)
      {:ok, socket |> assign(:presence_user, user) |> assign(:presence_account, account)}
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  def handle_info(:after_join, socket) do
    %{presence_user: user, presence_account: account} = socket.assigns

    {:ok, _} =
      Presence.track(self(), Presence.topic(account), to_string(user.id), %{
        handle: Accounts.get_account_from_user(user).name,
        online_at: System.system_time(:second)
      })

    push(socket, "presence_state", Presence.list(Presence.topic(account)))
    {:noreply, socket}
  end

  def handle_info(%Broadcast{event: "presence_diff", payload: diff}, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  def handle_info(:recheck, socket) do
    %{presence_user: user, presence_account: account} = socket.assigns

    with {:ok, current} <- ThreadsSocket.authenticate(socket.assigns.bearer),
         true <- current.id == user.id,
         {:ok, current_account} <- Accounts.get_account_by_id(account.id),
         :ok <- Halls.authorize(current, current_account) do
      Process.send_after(self(), :recheck, @recheck_interval)
      {:noreply, socket}
    else
      # Stopping untracks the user on every replica.
      _ -> {:stop, :normal, socket}
    end
  end
end
