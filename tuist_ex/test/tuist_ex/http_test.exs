defmodule TuistEx.HTTPTest do
  use ExUnit.Case, async: false

  alias TuistEx.HTTP

  @applications [:inets, :ssl, :public_key, :asn1]

  # Mix prunes the OTP code paths while it compiles dependencies, so an
  # application that is already running can be left without its code path
  # and unable to load the modules it has not used yet.
  setup do
    paths =
      Map.new(
        @applications,
        &{&1, :code.lib_dir(&1) |> Path.join("ebin") |> String.to_charlist()}
      )

    for application <- Enum.reverse(@applications), do: Application.stop(application)

    for {module, file} <- :code.all_loaded(),
        is_list(file),
        Enum.any?(Map.values(paths), &List.starts_with?(file, &1)) do
      :code.delete(module)
      :code.purge(module)
    end

    {:ok, _} = Application.ensure_all_started([:inets, :ssl])

    for {_application, path} <- paths, do: true = :code.del_path(path)

    on_exit(fn ->
      for {_application, path} <- paths,
          path not in :code.get_path(),
          do: true = :code.add_path(path)
    end)

    :ok
  end

  test "request/4 reads a chunked body after the code paths were pruned" do
    url =
      serve("http", fn client ->
        body = ~s({"access_token":"token","expires_in":3600})

        :gen_tcp.send(client, [
          "HTTP/1.1 200 OK\r\n",
          "content-type: application/json\r\n",
          "transfer-encoding: chunked\r\n",
          "connection: close\r\n\r\n",
          Integer.to_string(byte_size(body), 16),
          "\r\n",
          body,
          "\r\n0\r\n\r\n"
        ])
      end)

    assert {:ok, 200, %{"access_token" => "token", "expires_in" => 3600}} =
             HTTP.request(:post, url, %{})
  end

  test "request/4 attempts a TLS handshake after the code paths were pruned" do
    url = serve("https", fn _client -> :ok end)

    assert {:error, _reason} = HTTP.request(:get, url)
  end

  @tag :tmp_dir
  test "request/4 deflates a body holding a JSON file, reading the file into it", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "evidence.json")
    File.write!(path, ~s({"scopes":[{"kind":"test","files":[0]}],"paths":["lib/a.ex"]}))
    parent = self()

    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)

    spawn_link(fn ->
      {:ok, client} = :gen_tcp.accept(socket)
      send(parent, {:request, read_request(client, "")})
      :gen_tcp.send(client, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\n{}")
      :gen_tcp.close(client)
    end)

    body = %{name: "run", coverage_evidence: %HTTP.JSONFile{path: path}}
    assert {:ok, 200, %{}} = HTTP.request(:post, "http://127.0.0.1:#{port}/", body)

    assert_receive {:request, {headers, compressed}}
    assert headers =~ ~r/content-encoding: deflate/i

    z = :zlib.open()
    :ok = :zlib.inflateInit(z, -15)
    inflated = z |> :zlib.inflate(compressed) |> IO.iodata_to_binary()
    :zlib.close(z)

    assert JSON.decode!(inflated) == %{
             "name" => "run",
             "coverage_evidence" => %{
               "scopes" => [%{"kind" => "test", "files" => [0]}],
               "paths" => ["lib/a.ex"]
             }
           }
  end

  defp read_request(client, buffer) do
    {:ok, data} = :gen_tcp.recv(client, 0)
    buffer = buffer <> data

    with [headers, body] <- String.split(buffer, "\r\n\r\n", parts: 2),
         [_, length] <- Regex.run(~r/content-length: (\d+)/i, headers),
         true <- byte_size(body) >= String.to_integer(length) do
      {headers, body}
    else
      _ -> read_request(client, buffer)
    end
  end

  defp serve(scheme, respond) do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)

    spawn_link(fn ->
      {:ok, client} = :gen_tcp.accept(socket)
      {:ok, _request} = :gen_tcp.recv(client, 0)
      respond.(client)
      :gen_tcp.close(client)
    end)

    "#{scheme}://127.0.0.1:#{port}/"
  end
end
