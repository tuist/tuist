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
