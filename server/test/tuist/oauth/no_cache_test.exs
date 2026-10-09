defmodule Tuist.OAuth.NoCacheTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Boruta.Ecto.Client
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.NoCache
  alias Tuist.Repo

  test "Boruta uses an inert entity cache, not cluster replication" do
    assert Boruta.Config.cache_backend() == NoCache
    assert :ok = NoCache.put(:grant, %{revoked_at: nil}, ttl: 60_000)
    assert NoCache.get(:grant) == nil
    assert :ok = NoCache.delete(:grant)
  end

  test "client changes are visible after an earlier lookup" do
    {:ok, client} = Clients.create_client(%{redirect_uris: ["http://localhost:3000/callback"], name: "before"})
    assert Clients.get_client(client.id).name == "before"
    Client |> Repo.get!(client.id) |> Ecto.Changeset.change(name: "after") |> Repo.update!()
    assert Clients.get_client(client.id).name == "after"
  end
end
