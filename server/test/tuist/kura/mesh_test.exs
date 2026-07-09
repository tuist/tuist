defmodule Tuist.Kura.MeshTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura
  alias Tuist.Kura.Mesh
  alias Tuist.Kura.Registrations
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp csr_pem(subject \\ "/CN=node") do
    :secp256r1
    |> X509.PrivateKey.new_ec()
    |> X509.CSR.new(subject)
    |> X509.CSR.to_pem()
  end

  # Stubs the account's controller-managed peer CA (the `kura-<handle>-peer-ca`
  # secret) and a managed server so the cluster that holds it can be resolved.
  # Returns the CA certificate so the test can assert the leaf chains to it.
  defp stub_account_peer_ca do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca_cert = X509.Certificate.self_signed(ca_key, "/CN=kura test peer CA", template: :root_ca)

    data = %{
      "ca.pem" => Base.encode64(X509.Certificate.to_pem(ca_cert)),
      "ca-key.pem" => Base.encode64(X509.PrivateKey.to_pem(ca_key))
    }

    stub(Kura, :server_regions_for_account, fn _ -> ["local-controller"] end)
    stub(Client, :get, fn _path, _opts -> {:ok, %{"data" => data}} end)

    ca_cert
  end

  describe "sign_node_certificate/3" do
    test "issues a leaf that chains to the account CA with an issuer-controlled SAN" do
      account = AccountsFixtures.organization_fixture().account
      ca_cert = stub_account_peer_ca()

      assert {:ok, %{certificate_pem: leaf_pem, ca_certificate_pem: ca_pem}} =
               Mesh.sign_node_certificate(account, csr_pem(), ["kura-1.acme.test"])

      leaf_der = leaf_pem |> X509.Certificate.from_pem!() |> X509.Certificate.to_der()
      ca_der = X509.Certificate.to_der(ca_cert)

      assert ca_pem == X509.Certificate.to_pem(ca_cert)
      assert {:ok, _} = :public_key.pkix_path_validation(ca_der, [leaf_der], [])

      {:Extension, _oid, _critical, san_entries} =
        leaf_pem |> X509.Certificate.from_pem!() |> X509.Certificate.extension(:subject_alt_name)

      assert {:dNSName, ~c"kura-1.acme.test"} in san_entries
    end

    test "rejects an invalid CSR" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()
      assert Mesh.sign_node_certificate(account, "not a csr", ["host"]) == {:error, :invalid_csr}
    end

    test "fails when the account has no controller-managed CA yet" do
      account = AccountsFixtures.organization_fixture().account
      stub(Kura, :server_regions_for_account, fn _ -> [] end)

      assert Mesh.sign_node_certificate(account, csr_pem(), ["host"]) == {:error, :ca_unavailable}
    end
  end

  describe "enroll_node/2" do
    test "signs, registers the node endpoint, and returns the mesh config" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      assert {:ok, enrollment} =
               Mesh.enroll_node(account, %{
                 csr: csr_pem(),
                 node_url: "https://kura-1.acme.test:4433"
               })

      assert enrollment.tenant_id == account.name
      assert enrollment.certificate_pem =~ "BEGIN CERTIFICATE"
      assert enrollment.ca_certificate_pem =~ "BEGIN CERTIFICATE"
      assert is_integer(enrollment.renew_after_seconds)
      assert enrollment.peers == []
      assert enrollment.managed_peers == []

      assert [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      assert endpoint.url == "https://kura-1.acme.test:4433"
    end

    test "a second node sees the first as a peer and re-enrollment is idempotent" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://kura-1.acme.test:4433"})

      {:ok, second} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://kura-2.acme.test:4433"})

      assert second.peers == ["https://kura-1.acme.test:4433"]

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://kura-1.acme.test:4433"})

      assert length(Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)) == 2
    end

    test "rejects an invalid node URL" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      assert Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "not-a-url"}) ==
               {:error, :invalid_node_url}
    end

    test "re-enrollment refreshes the endpoint's liveness marker" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://kura-1.acme.test:4433"})

      [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      age_endpoint(endpoint, minutes: 90)

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://kura-1.acme.test:4433"})

      [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      assert DateTime.diff(DateTime.utc_now(), endpoint.updated_at, :minute) < 5
    end

    test "seeds the managed region's public peer endpoint so the node dials the managed mesh" do
      account = AccountsFixtures.organization_fixture().account

      ca_key = X509.PrivateKey.new_ec(:secp256r1)
      ca_cert = X509.Certificate.self_signed(ca_key, "/CN=kura test peer CA", template: :root_ca)

      data = %{
        "ca.pem" => Base.encode64(X509.Certificate.to_pem(ca_cert)),
        "ca-key.pem" => Base.encode64(X509.PrivateKey.to_pem(ca_key))
      }

      stub(Kura, :server_regions_for_account, fn _ -> ["eu-central"] end)
      stub(Client, :get, fn _path, _opts -> {:ok, %{"data" => data}} end)

      {:ok, enrollment} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://kura-1.acme.test:4433"})

      expected = "https://peer.#{String.downcase(account.name)}-eu-central-1.kura.tuist.dev:7443"
      assert expected in enrollment.peers
      # Split out for the node's static seed: platform-stable managed
      # endpoints only, so volatile self-hosted membership stays dynamic.
      assert enrollment.managed_peers == [expected]
    end
  end

  describe "heartbeat_node/2" do
    test "refreshes the liveness marker of the heartbeating node only and returns the mesh view" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://kura-1.acme.test:4433"})

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://kura-2.acme.test:4433"})

      account
      |> Accounts.list_account_cache_endpoints(:kura_self_hosted_peer)
      |> Enum.each(&age_endpoint(&1, minutes: 90))

      assert %{mesh_member: true, peers: peers} =
               Mesh.heartbeat_node(account, "https://kura-1.acme.test:4433")

      assert peers == ["https://kura-2.acme.test:4433"]

      endpoints = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      touched = Enum.find(endpoints, &(&1.url == "https://kura-1.acme.test:4433"))
      untouched = Enum.find(endpoints, &(&1.url == "https://kura-2.acme.test:4433"))

      assert DateTime.diff(DateTime.utc_now(), touched.updated_at, :minute) < 5
      assert DateTime.diff(DateTime.utc_now(), untouched.updated_at, :minute) >= 90
    end

    test "reports mesh_member: false for a node that never enrolled and never creates membership" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      assert %{mesh_member: false} =
               Mesh.heartbeat_node(account, "https://stranger.acme.test:4433")

      assert Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer) == []
    end
  end

  describe "sweep_stale_self_hosted_peers/1" do
    test "deactivates peers whose liveness marker lapsed" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://gone.acme.test:4433"})

      [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      age_endpoint(endpoint, minutes: 90)

      assert %{deactivated: [deactivated], purged: []} = Mesh.sweep_stale_self_hosted_peers()
      assert deactivated.url == "https://gone.acme.test:4433"

      # The row survives, withheld from the mesh; the returning node's
      # recovery re-enrollment reactivates it in place.
      assert [kept] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      assert kept.deactivated_at
      assert Mesh.self_hosted_peer_urls(account) == []
    end

    test "keeps peers whose liveness marker is fresh" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://fresh.acme.test:4433"})

      assert %{deactivated: [], purged: []} = Mesh.sweep_stale_self_hosted_peers()

      assert Mesh.self_hosted_peer_urls(account) == ["https://fresh.acme.test:4433"]
    end

    test "purges peers deactivated for longer than the certificate lifetime" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://expired.acme.test:4433"})

      [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      deactivate_endpoint(endpoint, days_ago: 31)

      assert %{deactivated: [], purged: [purged]} = Mesh.sweep_stale_self_hosted_peers()
      assert purged.url == "https://expired.acme.test:4433"
      assert Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer) == []
    end
  end

  describe "reactivation" do
    test "a mesh heartbeat from a deactivated node reports non-membership and leaves the row untouched" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://back.acme.test:4433"})

      [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      deactivate_endpoint(endpoint, days_ago: 1)
      [deactivated] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)

      # Heartbeats never restore membership: the node is told to re-enroll,
      # which is its trigger to re-bootstrap the data it missed.
      assert %{mesh_member: false} = Mesh.heartbeat_node(account, "https://back.acme.test:4433")

      assert Mesh.self_hosted_peer_urls(account) == []
      [unchanged] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      assert unchanged.deactivated_at == deactivated.deactivated_at
      assert unchanged.updated_at == deactivated.updated_at
    end

    test "re-enrollment rejoins a deactivated node to the mesh" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://back.acme.test:4433"})

      [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      deactivate_endpoint(endpoint, days_ago: 1)

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://back.acme.test:4433"})

      assert Mesh.self_hosted_peer_urls(account) == ["https://back.acme.test:4433"]
    end

    test "registration heartbeats do not affect mesh membership" do
      account = AccountsFixtures.organization_fixture().account
      stub_account_peer_ca()

      {:ok, _} =
        Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "https://back.acme.test:4433"})

      [endpoint] = Accounts.list_account_cache_endpoints(account, :kura_self_hosted_peer)
      deactivate_endpoint(endpoint, days_ago: 1)

      {:ok, _} =
        Registrations.register_heartbeat(account, %{
          node_id: "back.acme.test",
          advertised_http_url: "https://cache.acme.test",
          ready: true
        })

      # The two heartbeats are independent: registration advertises the
      # client-facing endpoint and plays no role in mesh membership.
      assert Mesh.self_hosted_peer_urls(account) == []
    end
  end

  defp age_endpoint(endpoint, minutes: minutes) do
    aged =
      DateTime.utc_now()
      |> DateTime.add(-minutes * 60, :second)
      |> DateTime.truncate(:second)

    {1, _} =
      Repo.update_all(
        from(e in AccountCacheEndpoint, where: e.id == ^endpoint.id),
        set: [updated_at: aged]
      )
  end

  defp deactivate_endpoint(endpoint, days_ago: days) do
    deactivated_at =
      DateTime.utc_now()
      |> DateTime.add(-days * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    {1, _} =
      Repo.update_all(
        from(e in AccountCacheEndpoint, where: e.id == ^endpoint.id),
        set: [deactivated_at: deactivated_at]
      )
  end
end
