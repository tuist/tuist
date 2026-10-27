defmodule Tuist.Kura.RegistrationsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Kura.RegisteredEndpoint
  alias Tuist.Kura.Registrations
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    %{account: account} = AccountsFixtures.organization_fixture(preload: [:account])
    %{account: account}
  end

  describe "register_heartbeat/2" do
    test "creates a registered endpoint and sets a fresh lease", %{account: account} do
      assert {:ok, endpoint} =
               Registrations.register_heartbeat(account, %{
                 node_id: "kura-0",
                 advertised_http_url: "https://cache.acme.internal",
                 region: "us-office",
                 ready: true,
                 version: "0.5.2",
                 traffic_state: "serving"
               })

      assert endpoint.node_id == "kura-0"
      assert endpoint.advertised_http_url == "https://cache.acme.internal"
      assert endpoint.ready
      assert DateTime.diff(endpoint.expires_at, endpoint.last_heartbeat_at) == Registrations.lease_seconds()
    end

    test "upserts by node_id and refreshes the lease + metadata", %{account: account} do
      {:ok, first} =
        Registrations.register_heartbeat(account, %{
          node_id: "kura-0",
          advertised_http_url: "https://cache.acme.internal",
          ready: false,
          traffic_state: "joining"
        })

      {:ok, second} =
        Registrations.register_heartbeat(account, %{
          node_id: "kura-0",
          advertised_http_url: "https://cache.acme.internal",
          ready: true,
          traffic_state: "serving"
        })

      assert first.id == second.id
      assert second.ready
      assert second.traffic_state == "serving"
      assert Repo.aggregate(RegisteredEndpoint, :count) == 1
    end

    test "rejects an advertised URL with embedded credentials", %{account: account} do
      assert {:error, changeset} =
               Registrations.register_heartbeat(account, %{
                 node_id: "kura-0",
                 advertised_http_url: "https://user:pass@cache.acme.internal",
                 ready: true
               })

      refute changeset.valid?
    end
  end

  describe "active_advertised_urls/1" do
    test "returns only ready, non-expired endpoints, deduped by URL", %{account: account} do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      insert_endpoint(account, "kura-0", "https://cache.acme.internal", ready: true, expires_at: DateTime.add(now, 120))
      insert_endpoint(account, "kura-1", "https://cache.acme.internal", ready: true, expires_at: DateTime.add(now, 120))
      insert_endpoint(account, "kura-2", "https://other.acme.internal", ready: false, expires_at: DateTime.add(now, 120))
      insert_endpoint(account, "kura-3", "https://stale.acme.internal", ready: true, expires_at: DateTime.add(now, -10))

      assert Registrations.active_advertised_urls(account) == ["https://cache.acme.internal"]
    end
  end

  describe "delete_expired/1" do
    test "removes only endpoints past their lease", %{account: account} do
      now = DateTime.truncate(DateTime.utc_now(), :second)
      insert_endpoint(account, "live", "https://live.acme.internal", ready: true, expires_at: DateTime.add(now, 120))
      insert_endpoint(account, "dead", "https://dead.acme.internal", ready: true, expires_at: DateTime.add(now, -1))

      assert Registrations.delete_expired() == 1
      assert Repo.aggregate(RegisteredEndpoint, :count) == 1
    end
  end

  defp insert_endpoint(account, node_id, url, opts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %RegisteredEndpoint{}
    |> RegisteredEndpoint.changeset(%{
      account_id: account.id,
      node_id: node_id,
      advertised_http_url: url,
      ready: Keyword.get(opts, :ready, true),
      last_heartbeat_at: now,
      expires_at: Keyword.fetch!(opts, :expires_at)
    })
    |> Repo.insert!()
  end
end
