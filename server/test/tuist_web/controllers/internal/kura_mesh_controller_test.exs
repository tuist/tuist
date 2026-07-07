defmodule TuistWeb.Internal.KuraMeshControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Kubernetes.Client
  alias Tuist.Kura
  alias Tuist.Kura.SelfHostedClients
  alias Tuist.Kura.Server
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp csr_pem do
    :secp256r1
    |> X509.PrivateKey.new_ec()
    |> X509.CSR.new("/CN=node")
    |> X509.CSR.to_pem()
  end

  defp basic_auth(conn, client_id, secret) do
    put_req_header(conn, "authorization", "Basic " <> Base.encode64("#{client_id}:#{secret}"))
  end

  # Stubs the account's controller-managed peer CA so enrollment can sign leaves.
  defp stub_account_peer_ca do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca_cert = X509.Certificate.self_signed(ca_key, "/CN=kura test peer CA", template: :root_ca)

    data = %{
      "ca.pem" => Base.encode64(X509.Certificate.to_pem(ca_cert)),
      "ca-key.pem" => Base.encode64(X509.PrivateKey.to_pem(ca_key))
    }

    stub(Kura, :list_servers_for_account, fn _ -> [%Server{region: "local-controller"}] end)
    stub(Client, :get, fn _path, _opts -> {:ok, %{"data" => data}} end)
  end

  setup do
    # A non-hosted (self-managed) deployment grants every entitlement, so the
    # self-hosted-cache gate in SelfHostedClients.verify/2 stays open here.
    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
    account = AccountsFixtures.organization_fixture().account

    {:ok, {client, secret}} =
      SelfHostedClients.create_self_hosted_client(account, %{name: "mesh"})

    stub_account_peer_ca()
    %{account: account, client: client, secret: secret}
  end

  test "enrolls a node with a valid credential", %{
    conn: conn,
    account: account,
    client: client,
    secret: secret
  } do
    conn =
      conn
      |> basic_auth(client.client_id, secret)
      |> post(~p"/_internal/kura/mesh/enroll", %{
        csr: csr_pem(),
        node_url: "https://kura-1.acme.test:4433"
      })

    assert %{
             "tenant_id" => tenant_id,
             "certificate" => certificate,
             "ca_certificate" => ca_certificate,
             "peers" => [],
             "renew_after_seconds" => renew_after_seconds
           } = json_response(conn, 201)

    assert tenant_id == account.name
    assert certificate =~ "BEGIN CERTIFICATE"
    assert ca_certificate =~ "BEGIN CERTIFICATE"
    assert is_integer(renew_after_seconds)
  end

  test "rejects a wrong secret", %{conn: conn, client: client} do
    conn =
      conn
      |> basic_auth(client.client_id, "wrong")
      |> post(~p"/_internal/kura/mesh/enroll", %{
        csr: csr_pem(),
        node_url: "https://kura-1.acme.test:4433"
      })

    assert json_response(conn, 401)
  end

  test "rejects an invalid CSR", %{conn: conn, client: client, secret: secret} do
    conn =
      conn
      |> basic_auth(client.client_id, secret)
      |> post(~p"/_internal/kura/mesh/enroll", %{
        csr: "not a csr",
        node_url: "https://kura-1.acme.test:4433"
      })

    assert json_response(conn, 422)
  end

  test "returns 503 when the account has no controller-managed CA yet", %{
    conn: conn,
    client: client,
    secret: secret
  } do
    stub(Kura, :list_servers_for_account, fn _ -> [] end)

    conn =
      conn
      |> basic_auth(client.client_id, secret)
      |> post(~p"/_internal/kura/mesh/enroll", %{
        csr: csr_pem(),
        node_url: "https://kura-1.acme.test:4433"
      })

    assert json_response(conn, 503) == %{"error" => "ca_unavailable"}
  end

  test "registers a heartbeat with a valid credential", %{
    conn: conn,
    account: account,
    client: client,
    secret: secret
  } do
    conn =
      conn
      |> basic_auth(client.client_id, secret)
      |> post(~p"/_internal/kura/mesh/registrations", %{
        node_id: "kura-0",
        tenant_id: account.name,
        advertised_http_url: "https://cache.acme.internal",
        ready: true,
        version: "0.5.2"
      })

    assert %{
             "accepted" => true,
             "lease_seconds" => lease,
             "heartbeat_interval_seconds" => interval
           } =
             json_response(conn, 200)

    assert is_integer(lease) and is_integer(interval)
  end

  test "registers a heartbeat with the deployment-level Kura control-plane credential", %{
    conn: conn,
    account: account
  } do
    stub(Tuist.Environment, :kura_control_plane_configured?, fn -> true end)
    stub(Tuist.Environment, :kura_control_plane_client_id, fn -> "static-kura-client" end)
    stub(Tuist.Environment, :kura_control_plane_client_secret, fn -> "static-kura-secret" end)

    conn =
      conn
      |> basic_auth("static-kura-client", "static-kura-secret")
      |> post(~p"/_internal/kura/mesh/registrations", %{
        node_id: "kura-0",
        tenant_id: account.name,
        advertised_http_url: "https://cache.acme.internal",
        ready: true,
        version: "0.5.2"
      })

    assert %{"accepted" => true} = json_response(conn, 200)
  end

  test "rejects deployment-level registration without a tenant", %{conn: conn} do
    stub(Tuist.Environment, :kura_control_plane_configured?, fn -> true end)
    stub(Tuist.Environment, :kura_control_plane_client_id, fn -> "static-kura-client" end)
    stub(Tuist.Environment, :kura_control_plane_client_secret, fn -> "static-kura-secret" end)

    conn =
      conn
      |> basic_auth("static-kura-client", "static-kura-secret")
      |> post(~p"/_internal/kura/mesh/registrations", %{
        node_id: "kura-0",
        advertised_http_url: "https://cache.acme.internal",
        ready: true,
        version: "0.5.2"
      })

    assert json_response(conn, 401)
  end

  test "rejects a registration heartbeat with invalid credentials", %{conn: conn} do
    conn =
      conn
      |> basic_auth("cache_bogus", "wrong")
      |> post(~p"/_internal/kura/mesh/registrations", %{
        node_id: "kura-0",
        advertised_http_url: "https://cache.acme.internal"
      })

    assert json_response(conn, 401)
  end

  test "rejects a registration heartbeat whose tenant does not match the account", %{
    conn: conn,
    client: client,
    secret: secret
  } do
    conn =
      conn
      |> basic_auth(client.client_id, secret)
      |> post(~p"/_internal/kura/mesh/registrations", %{
        node_id: "kura-0",
        tenant_id: "someone-else",
        advertised_http_url: "https://cache.acme.internal"
      })

    assert json_response(conn, 409)
  end
end
