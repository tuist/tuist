defmodule TuistEx.CertificateTrustTransportTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistEx.Cache.Reapi
  alias TuistEx.CertificateTrust
  alias TuistEx.HTTP

  setup do
    {:ok, _} = Application.ensure_all_started(:ssl)
    key = [digest: :sha256, key: {:rsa, 2048, 65_537}]

    configuration =
      :public_key.pkix_test_data(%{
        root: key,
        intermediates: [key],
        peer:
          key ++
            [extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]]
      })

    [root, intermediate] = Enum.uniq(configuration[:cacerts])
    leaf = configuration[:cert]

    configuration =
      configuration |> Keyword.put(:cert, [leaf, intermediate]) |> Keyword.put(:cacerts, [])

    %{configuration: configuration, root: root, intermediate: intermediate, leaf: leaf}
  end

  for operation <- [:request, :upload, :download] do
    @tag :tmp_dir
    test "#{operation} uses protected TLS and denies before delivering credentials or bodies",
         context do
      operation = unquote(operation)

      for additional <- [[], [spki(context.intermediate)]] do
        expect(CertificateTrust, :ssl_options, fn ->
          CertificateTrust.ssl_options([context.root], additional)
        end)

        {url, server, listener} = serve(context.configuration)

        result = perform(operation, url, context.tmp_dir)

        server_result = Task.await(server, 10_000)
        :ssl.close(listener)

        if additional == [] do
          assert_success(operation, result, context.tmp_dir)

          assert {:application_data, _request} = server_result
        else
          assert {:error, _} = result
          assert {:error, {:tls_alert, {_alert, _private_details}}} = server_result
        end
      end
    end
  end

  test "REAPI uses protected Mint credentials and denies before h2 application data", context do
    for additional <- [[], [spki(context.intermediate)]] do
      expect(CertificateTrust, :ssl_options, fn ->
        CertificateTrust.ssl_options([context.root], additional)
      end)

      {url, server, listener} = serve(context.configuration, :h2)

      result =
        Reapi.connect(url, "synthetic-token", %{account: "account", project: "project"}, "build")

      if match?({:ok, _}, result), do: Reapi.close(elem(result, 1))
      server_result = Task.await(server, 10_000)
      :ssl.close(listener)

      if additional == [] do
        # This is a TLS/h2-preface positive, not a successful capabilities RPC.
        assert {:h2_preface, "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"} = server_result
      else
        assert {:error, _} = result
        assert {:error, {:tls_alert, {_alert, _private_details}}} = server_result
      end
    end
  end

  defp perform(:request, url, _directory) do
    HTTP.request(:post, url, %{payload: "private-body"}, [
      {"authorization", "Bearer synthetic-token"}
    ])
  end

  defp perform(:upload, url, _directory), do: HTTP.put_binary(url, "private-body")

  defp perform(:download, url, directory),
    do: HTTP.download(url, Path.join(directory, "download"))

  defp assert_success(:request, result, _directory),
    do: assert({:ok, 200, %{"ok" => true}} = result)

  defp assert_success(:upload, result, _directory), do: assert({:ok, "test-etag"} = result)

  defp assert_success(:download, result, directory) do
    assert :ok = result
    assert File.read!(Path.join(directory, "download")) == ~s({"ok":true})
  end

  defp serve(configuration, protocol \\ :http1) do
    {:ok, listener} =
      :ssl.listen(
        0,
        configuration ++
          [mode: :binary, active: false, reuseaddr: true, alpn_preferred_protocols: ["h2"]]
      )

    on_exit(fn -> :ssl.close(listener) end)
    {:ok, {_, port}} = :ssl.sockname(listener)

    server =
      Task.async(fn ->
        with {:ok, socket} <- :ssl.transport_accept(listener, 30_000),
             {:ok, socket} <- :ssl.handshake(socket, 5_000) do
          try do
            respond(socket, protocol)
          after
            :ssl.close(socket)
          end
        end
      end)

    {"https://localhost:#{port}", server, listener}
  end

  defp respond(socket, :h2) do
    {:ok, preface} = :ssl.recv(socket, 24, 5_000)
    {:h2_preface, preface}
  end

  defp respond(socket, :http1) do
    request = receive_request(socket, "")
    body = ~s({"ok":true})

    :ok =
      :ssl.send(socket, [
        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\netag: test-etag\r\n",
        "connection: close\r\ncontent-length: #{byte_size(body)}\r\n\r\n",
        body
      ])

    {:application_data, request}
  end

  defp receive_request(socket, accumulated) do
    case String.split(accumulated, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        length =
          case Regex.run(~r/content-length:\s*(\d+)/i, headers) do
            [_, value] -> String.to_integer(value)
            nil -> 0
          end

        if byte_size(body) >= length do
          accumulated
        else
          {:ok, data} = :ssl.recv(socket, 0, 5_000)
          receive_request(socket, accumulated <> data)
        end

      _ ->
        {:ok, data} = :ssl.recv(socket, 0, 5_000)
        receive_request(socket, accumulated <> data)
    end
  end

  defp spki(der) do
    {:Certificate, tbs, _, _} = :public_key.pkix_decode_cert(der, :plain)

    :sha256
    |> :crypto.hash(:public_key.der_encode(:SubjectPublicKeyInfo, elem(tbs, 7)))
    |> Base.encode16(case: :lower)
  end
end
