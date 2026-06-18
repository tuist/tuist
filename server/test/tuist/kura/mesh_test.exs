defmodule Tuist.Kura.MeshTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Kura.Mesh
  alias Tuist.Kura.MeshCertificateAuthority
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp csr_pem(subject \\ "/CN=node") do
    :secp256r1
    |> X509.PrivateKey.new_ec()
    |> X509.CSR.new(subject)
    |> X509.CSR.to_pem()
  end

  describe "get_or_create_certificate_authority/1" do
    test "creates the CA once and reuses it" do
      account = AccountsFixtures.organization_fixture().account

      assert {:ok, %MeshCertificateAuthority{} = ca} =
               Mesh.get_or_create_certificate_authority(account)

      assert ca.certificate_pem =~ "BEGIN CERTIFICATE"

      assert {:ok, %MeshCertificateAuthority{id: reused_id}} =
               Mesh.get_or_create_certificate_authority(account)

      assert reused_id == ca.id
    end
  end

  describe "sign_node_certificate/3" do
    test "issues a leaf that chains to the account CA with an issuer-controlled SAN" do
      account = AccountsFixtures.organization_fixture().account

      assert {:ok, %{certificate_pem: leaf_pem, ca_certificate_pem: ca_pem}} =
               Mesh.sign_node_certificate(account, csr_pem(), ["kura-1.acme.test"])

      leaf_der = leaf_pem |> X509.Certificate.from_pem!() |> X509.Certificate.to_der()
      ca_der = ca_pem |> X509.Certificate.from_pem!() |> X509.Certificate.to_der()

      assert {:ok, _} = :public_key.pkix_path_validation(ca_der, [leaf_der], [])

      {:Extension, _oid, _critical, san_entries} =
        leaf_pem |> X509.Certificate.from_pem!() |> X509.Certificate.extension(:subject_alt_name)

      assert {:dNSName, ~c"kura-1.acme.test"} in san_entries
    end

    test "rejects an invalid CSR" do
      account = AccountsFixtures.organization_fixture().account
      assert Mesh.sign_node_certificate(account, "not a csr", ["host"]) == {:error, :invalid_csr}
    end
  end

  describe "issue_node_certificate/2" do
    test "issues a managed-node cert (server-generated key) chaining to the account CA" do
      account = AccountsFixtures.organization_fixture().account
      dns_names = ["*.kura-tuist-us-east-headless.kura.svc.cluster.local", "kura-tuist-us-east-headless"]

      assert {:ok, %{certificate_pem: leaf_pem, private_key_pem: key_pem, ca_certificate_pem: ca_pem}} =
               Mesh.issue_node_certificate(account, dns_names)

      assert key_pem =~ "BEGIN EC PRIVATE KEY"

      leaf_der = leaf_pem |> X509.Certificate.from_pem!() |> X509.Certificate.to_der()
      ca_der = ca_pem |> X509.Certificate.from_pem!() |> X509.Certificate.to_der()
      assert {:ok, _} = :public_key.pkix_path_validation(ca_der, [leaf_der], [])

      {:Extension, _oid, _critical, san_entries} =
        leaf_pem |> X509.Certificate.from_pem!() |> X509.Certificate.extension(:subject_alt_name)

      assert {:dNSName, ~c"kura-tuist-us-east-headless"} in san_entries

      # The issued key and certificate form a valid pair.
      assert {:ok, _} = X509.Certificate.from_pem(leaf_pem)
    end
  end

  describe "enroll_node/2" do
    test "signs, registers the node endpoint, and returns the mesh config" do
      account = AccountsFixtures.organization_fixture().account

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

      assert Mesh.enroll_node(account, %{csr: csr_pem(), node_url: "not-a-url"}) ==
               {:error, :invalid_node_url}
    end
  end
end
