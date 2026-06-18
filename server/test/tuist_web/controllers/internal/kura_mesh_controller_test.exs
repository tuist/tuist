defmodule TuistWeb.Internal.KuraMeshControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Kura.SelfHostedClients
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

  setup do
    account = AccountsFixtures.organization_fixture().account
    {:ok, {client, secret}} = SelfHostedClients.create_self_hosted_client(account, %{name: "mesh"})
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

  test "registers a heartbeat with a valid credential", %{conn: conn, account: account, client: client, secret: secret} do
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

    assert %{"accepted" => true, "lease_seconds" => lease, "heartbeat_interval_seconds" => interval} =
             json_response(conn, 200)

    assert is_integer(lease) and is_integer(interval)
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
