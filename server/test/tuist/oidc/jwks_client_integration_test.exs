defmodule Tuist.OIDC.JWKSClientIntegrationTest do
  use ExUnit.Case, async: true

  alias Tuist.OIDC.JWKSClient

  setup_all do
    ca_key = X509.PrivateKey.new_ec(:secp256r1)
    ca = X509.Certificate.self_signed(ca_key, "/CN=JWKS test CA", template: :root_ca)
    key = X509.PrivateKey.new_ec(:secp256r1)

    certificate =
      key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new("/CN=keys.example", ca, ca_key,
        extensions: [subject_alt_name: X509.Certificate.Extension.subject_alt_name(["keys.example"])]
      )
      |> X509.Certificate.to_der()

    %{certificate: certificate, ca: X509.Certificate.to_der(ca), key: {:ECPrivateKey, X509.PrivateKey.to_der(key)}}
  end

  setup %{certificate: certificate, ca: ca, key: key} do
    {:ok, listener} =
      :ssl.listen(0,
        cert: certificate,
        key: key,
        ip: {127, 0, 0, 1},
        active: false,
        mode: :binary,
        reuseaddr: true
      )

    on_exit(fn -> :ssl.close(listener) end)
    {:ok, {_address, port}} = :ssl.sockname(listener)

    opts = [
      connect_options: [
        hostname: "keys.example",
        transport_opts: [verify: :verify_peer, cacerts: [ca], server_name_indication: ~c"keys.example"],
        timeout: 5_000
      ]
    ]

    %{listener: listener, url: "https://127.0.0.1:#{port}/jwks", opts: opts}
  end

  test "a real TLS connection accepts bounded HTTP/1 response headers", context do
    server = respond(context.listener, ["x-provider: example\r\n"])

    try do
      assert {:ok, %{status: 200, body: ~s({"keys": []}), headers: headers}} =
               JWKSClient.get(context.url, context.opts)

      assert {"x-provider", "example"} in headers
      assert Task.await(server, 5_000) == {:error, :closed}
    after
      Task.shutdown(server, :brutal_kill)
    end
  end

  test "a real TLS connection rejects HTTP/1 response headers over 16 KiB", context do
    headers = Enum.map(1..20, &["x-padding-#{&1}: ", String.duplicate("a", 1_024), "\r\n"])
    server = respond(context.listener, headers)

    try do
      assert {:error, %Mint.HTTPError{reason: {:max_header_list_size_exceeded, size, 16_384}}} =
               JWKSClient.get(context.url, context.opts)

      assert size > 16_384
      assert Task.await(server, 5_000) == {:error, :closed}
    after
      Task.shutdown(server, :brutal_kill)
    end
  end

  defp respond(listener, headers) do
    Task.async(fn ->
      {:ok, socket} = :ssl.transport_accept(listener, 5_000)
      {:ok, socket} = :ssl.handshake(socket, 5_000)

      try do
        request = receive_headers(socket, "")
        assert request =~ "GET /jwks HTTP/1.1\r\n"
        assert request =~ "host: keys.example"

        :ok =
          :ssl.send(socket, [
            "HTTP/1.1 200 OK\r\n",
            "content-type: application/json\r\n",
            headers,
            "content-length: 12\r\n\r\n",
            ~s({"keys": []})
          ])

        :ssl.recv(socket, 0, 5_000)
      after
        :ssl.close(socket)
      end
    end)
  end

  defp receive_headers(socket, buffer) do
    if String.contains?(buffer, "\r\n\r\n") do
      buffer
    else
      {:ok, chunk} = :ssl.recv(socket, 0, 5_000)
      receive_headers(socket, buffer <> chunk)
    end
  end
end
