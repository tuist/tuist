defmodule Tuist.Agents.SessionStore do
  @moduledoc """
  Where durable agent sessions keep their conversation and journal: object
  storage, through `Condukt.SessionStore.ObjectStore`, under
  `agents/<kind>/<id>/`, with every object encrypted by `Tuist.Vault`.

  The writer's epoch is the session's lease epoch (`Tuist.Agents.Lease`), so
  a host that lost its lease is fenced out of the store by the next host's
  first call, on top of the lease itself. Postgres holds only the lease.

  The bucket is `Tuist.Agents.Bucket` unless
  `config :tuist, Tuist.Agents.SessionStore, bucket: {module, config}` says
  otherwise, as the test environment does.
  """

  alias Condukt.SessionStore.ObjectStore
  alias Tuist.Vault

  @doc "The `session_store:` option for the session `id` of `kind` at the lease `epoch`."
  def store(kind, id, epoch) do
    crypto = [encrypt: &Vault.encrypt!/1, decrypt: &Vault.decrypt!/1]
    {ObjectStore, [bucket: bucket(), prefix: prefix(kind), key: id, epoch: epoch] ++ crypto}
  end

  @doc "Deletes everything stored for the session `id` of `kind`."
  def delete(kind, id) do
    {module, config} = bucket()

    with {:ok, keys} <- module.list(config, "#{prefix(kind)}/#{id}/", nil) do
      Enum.reduce_while(keys, :ok, fn key, :ok ->
        case module.delete(config, key) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp prefix(kind), do: "agents/#{kind}"

  defp bucket do
    :tuist |> Application.get_env(__MODULE__, []) |> Keyword.get(:bucket, {Tuist.Agents.Bucket, []})
  end
end
