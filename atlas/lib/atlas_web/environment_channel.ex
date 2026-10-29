defmodule AtlasWeb.EnvironmentChannel do
  @moduledoc "Native device delivery hints. PostgreSQL, never this channel, owns command state."
  use AtlasWeb, :channel

  alias Atlas.Environments
  alias Atlas.Environments.Commands
  alias Atlas.Guardian
  alias AtlasWeb.Plugs.NativeOAuthClient

  @reconcile_interval 2_000

  @impl true
  def join("environment:" <> id, _params, socket) do
    connection_id = Ecto.UUID.generate()

    with {:ok, user, _claims} <- Guardian.resource_from_token(socket.assigns.access_token),
         {:ok, client_id} <- NativeOAuthClient.client_id(socket.assigns.access_token),
         {:ok, environment} <- Environments.renew(user, client_id, id, connection_id),
         {:ok, commands} <- Commands.queued(user, client_id, id) do
      snapshot = %{commands: commands}
      Process.send_after(self(), :reconcile, @reconcile_interval)

      {:ok, snapshot,
       assign(socket,
         environment_id: environment.id,
         environment_version: environment.version,
         connection_id: connection_id,
         snapshot_digest: snapshot_digest(snapshot)
       )}
    else
      _ -> {:error, %{reason: "unavailable"}}
    end
  end

  @impl true
  def handle_info(:reconcile, socket) do
    Process.send_after(self(), :reconcile, @reconcile_interval)
    refresh(socket)
  end

  @impl true
  def handle_in("renew", _params, socket), do: refresh(socket)
  def handle_in(_event, _params, socket), do: {:reply, {:error, %{reason: "unsupported"}}, socket}

  defp refresh(socket) do
    assigns = socket.assigns

    with {:ok, user, _claims} <- Guardian.resource_from_token(assigns.access_token),
         {:ok, client_id} <- NativeOAuthClient.client_id(assigns.access_token),
         {:ok, _environment} <-
           Environments.renew(
             user,
             client_id,
             assigns.environment_id,
             assigns.connection_id,
             assigns.environment_version
           ),
         {:ok, commands} <- Commands.queued(user, client_id, assigns.environment_id) do
      snapshot = %{commands: commands}
      digest = snapshot_digest(snapshot)
      if digest != assigns.snapshot_digest, do: push(socket, "snapshot", snapshot)
      {:noreply, assign(socket, :snapshot_digest, digest)}
    else
      _ -> {:stop, :normal, socket}
    end
  end

  # Never retain command arguments in the socket's inspectable crash state.
  defp snapshot_digest(snapshot), do: :crypto.hash(:sha256, :erlang.term_to_binary(snapshot, [:deterministic]))

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:environment_id],
      do: Environments.close(socket.assigns.environment_id, socket.assigns.connection_id)

    :ok
  end
end
