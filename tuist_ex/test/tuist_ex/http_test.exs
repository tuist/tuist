defmodule TuistEx.HTTPTest do
  # Removes OTP applications from the code path of the whole VM.
  use ExUnit.Case, async: false

  alias TuistEx.HTTP

  test "restores OTP code paths that Mix pruned while the applications kept running" do
    {:ok, _} = Application.ensure_all_started(:ssl)
    paths = Enum.map([:inets, :ssl, :public_key, :crypto, :asn1], &ebin/1)
    on_exit(fn -> Enum.each(paths, &:code.add_pathz/1) end)
    Enum.each(paths, &:code.del_path/1)

    assert {:ok, 200, %{"access_token" => "token"}} =
             HTTP.request(:post, serve_chunked(~s({"access_token":"token"})), %{token: "id"})

    assert Enum.all?(paths, &(&1 in :code.get_path()))
  end

  defp ebin(app), do: :code.lib_dir(app) |> Path.join("ebin") |> String.to_charlist()

  defp serve_chunked(body) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(socket, 0)
      size = Integer.to_string(byte_size(body), 16)

      :ok =
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n" <>
            size <> "\r\n" <> body <> "\r\n0\r\n\r\n"
        )

      :gen_tcp.close(socket)
    end)

    "http://127.0.0.1:#{port}/"
  end
end
