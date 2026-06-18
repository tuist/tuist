defmodule Tuist.Kura.MeshTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura
  alias Tuist.Kura.Mesh
  alias Tuist.Kura.Server
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

    stub(Kura, :list_servers_for_account, fn _ -> [%Server{region: "local-controller"}] end)
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
      stub(Kura, :list_servers_for_account, fn _ -> [] end)

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
  end
end
