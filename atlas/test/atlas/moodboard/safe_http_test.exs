defmodule Atlas.Moodboard.SafeHTTPTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Moodboard.Resolver
  alias Atlas.Moodboard.SafeHTTP
  alias Mint.HTTP

  setup :verify_on_exit!

  test "rejects local, reserved, transition, multicast and credentialed destinations" do
    for address <- [
          {127, 0, 0, 1},
          {10, 0, 0, 1},
          {169, 254, 169, 254},
          {100, 64, 0, 1},
          {192, 168, 1, 1},
          {198, 18, 0, 1},
          {192, 88, 99, 1},
          {203, 0, 113, 1},
          {225, 0, 0, 1},
          {240, 0, 0, 1},
          {0, 0, 0, 0, 0, 0, 0, 1},
          {0, 0, 0, 0, 0, 65_535, 0x7F00, 1},
          {0xFC00, 0, 0, 0, 0, 0, 0, 1},
          {0x2002, 0x7F00, 1, 0, 0, 0, 0, 1},
          {0x2001, 0, 0, 0, 0, 0, 0, 1}
        ] do
      refute SafeHTTP.public_address?(address), inspect(address)
    end

    assert SafeHTTP.public_address?({93, 184, 216, 34})
    assert SafeHTTP.public_address?({0x2606, 0x4700, 0x4700, 0, 0, 0, 0, 0x1111})

    for url <- [
          "http://example.com",
          "https://user:pass@example.com",
          "https://localhost",
          "https://example.com:444",
          "https://example.com/ bad",
          "file:///etc/passwd"
        ] do
      assert {:error, :unsafe_url} = SafeHTTP.fetch(url)
    end
  end

  test "rejects any mixed public/private DNS result before opening a socket" do
    expect(Resolver, :resolve, fn "design.example" -> {:ok, [{93, 184, 216, 34}, {10, 0, 0, 1}]} end)
    reject(HTTP, :connect, 4)
    assert {:error, :unsafe_url} = SafeHTTP.fetch("https://design.example/")
  end

  test "pins the validated address while retaining TLS hostname verification, and sends no credentials" do
    expect(Resolver, :resolve, fn "design.example" -> {:ok, [{93, 184, 216, 34}]} end)

    expect(HTTP, :connect, fn :https, {93, 184, 216, 34}, 443, opts ->
      assert opts[:hostname] == "design.example"
      assert opts[:transport_opts][:verify] == :verify_peer
      assert opts[:mode] == :passive
      assert opts[:protocols] == [:http1]
      {:ok, :connection}
    end)

    expect(HTTP, :request, fn :connection, "GET", "/article?q=design", headers, nil ->
      assert Enum.map(headers, &elem(&1, 0)) |> Enum.sort() == ["accept", "accept-encoding", "user-agent"]
      {:ok, :connection, :request}
    end)

    expect(HTTP, :recv, fn :connection, 0, timeout ->
      assert timeout in 1..12_000
      {:ok, :connection, events(200, [{"content-type", "text/html"}], "<title>Hello</title>")}
    end)

    expect(HTTP, :close, fn :connection -> {:ok, :closed} end)

    assert {:ok, %{status: 200, body: "<title>Hello</title>"}} =
             SafeHTTP.fetch("https://design.example/article?q=design#fragment")
  end

  test "revalidates redirect DNS and never connects to a private redirected host" do
    expect(Resolver, :resolve, fn "design.example" -> {:ok, [{93, 184, 216, 34}]} end)
    expect(Resolver, :resolve, fn "private.example" -> {:ok, [{10, 0, 0, 1}]} end)
    transport(events(302, [{"location", "https://private.example/metadata"}], ""))
    assert {:error, :unsafe_url} = SafeHTTP.fetch("https://design.example/")
  end

  test "rejects scheme-changing and credential-bearing redirects" do
    for location <- ["http://example.com/", "https://user:password@example.com/", "https://127.0.0.1/secret"] do
      stub(Resolver, :resolve, fn _host -> {:ok, [{93, 184, 216, 34}]} end)
      transport(events(302, [{"location", location}], ""))
      assert {:error, :unsafe_url} = SafeHTTP.fetch("https://design.example/")
    end
  end

  test "caps redirects and closes every connection" do
    expect(Resolver, :resolve, 4, fn _ -> {:ok, [{93, 184, 216, 34}]} end)
    transport(events(302, [{"location", "/loop"}], ""), 4)
    assert {:error, :redirect_rejected} = SafeHTTP.fetch("https://design.example/loop")
  end

  test "enforces body limits and rejects compression before parsing" do
    stub(Resolver, :resolve, fn _ -> {:ok, [{93, 184, 216, 34}]} end)
    transport(events(200, [], String.duplicate("a", 2_000_001)))
    assert {:error, :fetch_failed} = SafeHTTP.fetch("https://design.example/large")
    transport(events(200, [{"content-encoding", "gzip"}], "compressed"))
    assert {:error, :fetch_failed} = SafeHTTP.fetch("https://design.example/gzip")
  end

  test "stops at media headers rather than buffering a remote video" do
    stub(Resolver, :resolve, fn _ -> {:ok, [{93, 184, 216, 34}]} end)
    transport(events(200, [{"content-type", "video/mp4"}], String.duplicate("v", 2_000_001)))
    assert {:ok, %{body: "", status: 200}} = SafeHTTP.fetch("https://media.example/clip.mp4")
  end

  test "transport failures are sanitized and established sockets are closed" do
    stub(Resolver, :resolve, fn _ -> {:ok, [{93, 184, 216, 34}]} end)
    expect(HTTP, :connect, fn _, _, _, _ -> {:error, {:secret_transport_failure, "private-payload"}} end)
    assert {:error, :fetch_failed} = SafeHTTP.fetch("https://design.example/")
    expect(HTTP, :connect, fn _, _, _, _ -> {:ok, :connection} end)
    expect(HTTP, :request, fn _, _, _, _, _ -> {:error, :connection, :closed} end)
    expect(HTTP, :close, fn :connection -> {:ok, :closed} end)
    assert {:error, :fetch_failed} = SafeHTTP.fetch("https://design.example/")
  end

  test "DNS and transport failures return bounded failures" do
    expect(Resolver, :resolve, fn _ -> {:error, :dns_unavailable} end)
    assert {:error, :dns_unavailable} = SafeHTTP.fetch("https://design.example/")
    expect(Resolver, :resolve, fn _ -> {:ok, []} end)
    assert {:error, :unsafe_url} = SafeHTTP.fetch("https://design.example/")
  end

  defp events(status, headers, body) do
    [{:status, :request, status}, {:headers, :request, headers}, {:data, :request, body}, {:done, :request}]
  end

  defp transport(events, count \\ 1) do
    expect(HTTP, :connect, count, fn :https, {93, 184, 216, 34}, 443, _opts -> {:ok, :connection} end)
    expect(HTTP, :request, count, fn :connection, "GET", _path, _headers, nil -> {:ok, :connection, :request} end)
    expect(HTTP, :recv, count, fn :connection, 0, _timeout -> {:ok, :connection, events} end)
    expect(HTTP, :close, count, fn :connection -> {:ok, :closed} end)
  end
end
