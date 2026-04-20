defmodule Tuist.Scaleway.Stub do
  @moduledoc """
  In-memory stub that matches the `Tuist.Scaleway.Client` API.

  Used for local end-to-end runs against a kind cluster so the full Bonny →
  Reconciler → Oban → "Scaleway" pipeline can be exercised without touching
  real Scaleway APIs or booting a bare-metal Mac. Wire it up via
  `config :tuist, :scaleway_client, Tuist.Scaleway.Stub`.
  """

  require Logger

  def create_server(_config, attrs) do
    id = "stub-" <> rand_hex(6)
    name = Map.get(attrs, :name, "stub-worker")

    Logger.info("[Scaleway stub] create_server #{name} -> #{id}")

    {:ok,
     %{
       "id" => id,
       "name" => name,
       "ip" => "127.0.0.1",
       "ssh_username" => "stub",
       "sudo_password" => "stub-password-" <> rand_hex(4),
       "status" => "ready"
     }}
  end

  def get_server(_config, _zone, id) do
    {:ok, %{"id" => id, "status" => "ready"}}
  end

  def delete_server(_config, _zone, id) do
    Logger.info("[Scaleway stub] delete_server #{id}")
    :ok
  end

  def list_os(_config, _zone) do
    {:ok,
     %{
       "os" => [
         %{"id" => "stub-os-id", "name" => "macos-tahoe-26.0"}
       ]
     }}
  end

  def find_os_id(_config, _zone, _os_name) do
    {:ok, "stub-os-id"}
  end

  defp rand_hex(bytes), do: bytes |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end
