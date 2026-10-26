defmodule AtlasWeb.NativeExecutionChannel do
  use Phoenix.Channel, log_handle_in: false

  alias Atlas.Automations.Native
  alias Atlas.Automations.Notifier
  alias Atlas.Guardian

  @impl true
  def join("execution:" <> id, _params, socket) do
    with true <- id == socket.assigns.execution_id,
         :ok <- Phoenix.PubSub.subscribe(Atlas.PubSub, Notifier.topic(id)),
         {:ok, snapshot} <- snapshot(socket) do
      Process.send_after(self(), :reconcile, 5_000)
      {:ok, snapshot, assign(socket, :snapshot, snapshot)}
    else
      _ -> {:error, %{error: "forbidden"}}
    end
  end

  @impl true
  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{error: "unsupported"}}, socket}

  @impl true
  def handle_info(:reconcile, socket) do
    Process.send_after(self(), :reconcile, 5_000)
    reconcile(socket)
  end

  def handle_info(:automation_changed, socket), do: reconcile(socket)
  def handle_info(_, socket), do: {:noreply, socket}

  defp reconcile(socket) do
    case snapshot(socket) do
      {:ok, snapshot} ->
        if snapshot != socket.assigns.snapshot, do: push(socket, "snapshot", snapshot)
        {:noreply, assign(socket, :snapshot, snapshot)}

      _ ->
        push(socket, "access_revoked", %{})
        {:stop, :normal, socket}
    end
  end

  defp snapshot(socket) do
    with {:ok, actor, %{"typ" => "access_token"}} <- Guardian.resource_from_token(socket.assigns.credential.token),
         do: Native.execution(actor, socket.assigns.execution_id)
  end
end
