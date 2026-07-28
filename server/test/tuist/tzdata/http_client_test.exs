defmodule Tuist.Tzdata.HTTPClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Tzdata.HTTPClient

  test "returns a downloaded response in the shape expected by Tzdata" do
    expect(Req, :request, fn options ->
      assert options[:method] == :get
      assert options[:url] == "https://data.example.com/timezones"
      assert options[:headers] == [{"accept", "application/gzip"}]
      assert options[:redirect]
      assert options[:decode_body] == false

      {:ok,
       Req.Response.new(
         status: 200,
         headers: [{"last-modified", "Sun, 12 Jul 2026 10:00:00 GMT"}],
         body: "archive"
       )}
    end)

    assert HTTPClient.get(
             "https://data.example.com/timezones",
             [{"accept", "application/gzip"}],
             follow_redirect: true
           ) ==
             {:ok, {200, [{"last-modified", "Sun, 12 Jul 2026 10:00:00 GMT"}], "archive"}}
  end

  test "returns head responses without treating the body as a connection handle" do
    expect(Req, :request, fn options ->
      assert options[:method] == :head
      refute options[:redirect]

      {:ok, Req.Response.new(status: 200, headers: [{"content-length", "123"}])}
    end)

    assert HTTPClient.head("https://data.example.com/timezones", [], []) ==
             {:ok, {200, [{"content-length", "123"}]}}
  end

  test "passes transport errors through" do
    expect(Req, :request, fn _options -> {:error, :timeout} end)

    assert HTTPClient.get("https://data.example.com/timezones", [], []) == {:error, :timeout}
  end
end
