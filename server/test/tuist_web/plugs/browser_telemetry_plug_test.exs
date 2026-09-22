defmodule TuistWeb.Plugs.BrowserTelemetryPlugTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn
  import Plug.Test

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistWeb.Plugs.BrowserTelemetryPlug

  @session_options [store: :cookie, key: "_tuist_key", signing_salt: "test-salt", same_site: "Lax"]
  @receiver "http://alloy:12347/collect"

  setup do
    stub(Environment, :faro_receiver_url, fn -> @receiver end)
    stub(Environment, :app_url, fn -> "https://tuist.dev" end)
    stub(Environment, :env, fn -> :prod end)
    :ok
  end

  defp request(body \\ Jason.encode!(payload())) do
    :post
    |> conn("/-/faro/collect", body)
    |> Map.put(:secret_key_base, String.duplicate("a", 64))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("sec-fetch-site", "same-origin")
  end

  defp call(conn), do: BrowserTelemetryPlug.call(conn, BrowserTelemetryPlug.init(session_options: @session_options))

  defp payload do
    %{
      "meta" => %{"page" => %{"url" => "https://tuist.dev/tuist/tuist"}, "session" => %{"id" => "session"}},
      "measurements" => [
        %{"type" => "web-vitals", "values" => %{"lcp" => 2900}, "context" => %{"navigation_entry_id" => "nav"}}
      ]
    }
  end

  defp session_cookie(token) do
    conn =
      request()
      |> Plug.Session.call(Plug.Session.init(@session_options))
      |> fetch_session()
      |> put_session(:user_token, token)
      |> send_resp(200, "")

    conn.resp_cookies["_tuist_key"].value
  end

  test "validates the signed session against the server and forwards no browser credentials" do
    expect(Accounts, :get_user_by_session_token, fn "valid-token" -> %{id: "not-exported"} end)

    expect(Req, :post, fn @receiver, options ->
      [measurement] = options[:json]["measurements"]
      assert measurement["context"]["rum_authentication"] == "authenticated"
      assert measurement["context"]["rum_surface"] == "dashboard_authenticated"
      assert options[:retry] == false
      assert options[:redirect] == false
      refute Keyword.has_key?(options, :headers)
      refute inspect(options[:json]) =~ "valid-token"
      refute inspect(options[:json]) =~ "not-exported"
      {:ok, %Req.Response{status: 202}}
    end)

    response = request() |> put_req_cookie("_tuist_key", session_cookie("valid-token")) |> call()
    assert response.status == 202
    assert response.halted
    assert response.resp_cookies == %{}
    assert get_resp_header(response, "cache-control") == ["no-store"]
  end

  test "revoked and tampered sessions never get authenticated telemetry labels" do
    stub(Accounts, :get_user_by_session_token, fn "revoked" -> nil end)

    expect(Req, :post, 2, fn @receiver, options ->
      assert hd(options[:json]["measurements"])["context"]["rum_authentication"] == "anonymous"
      {:ok, %Req.Response{status: 202}}
    end)

    assert request() |> put_req_cookie("_tuist_key", session_cookie("revoked")) |> call() |> Map.fetch!(:status) == 202
    assert request() |> put_req_cookie("_tuist_key", "tampered") |> call() |> Map.fetch!(:status) == 202
  end

  test "only forwards a Ray ID observed through the trusted ingress path" do
    expect(Req, :post, fn @receiver, options ->
      assert hd(options[:json]["measurements"])["context"]["rum_ray_id"] == "a3e837c27a56c4cf-SEA"
      {:ok, %Req.Response{status: 202}}
    end)

    response =
      request()
      |> Map.put(:remote_ip, {10, 0, 0, 1})
      |> put_req_header("x-tuist-edge-address", "104.22.160.71")
      |> put_req_header("cf-ray", "a3e837c27a56c4cf-SEA")
      |> call()

    assert response.status == 202

    expect(Req, :post, fn @receiver, options ->
      assert hd(options[:json]["measurements"])["context"]["rum_ray_id"] == ""
      {:ok, %Req.Response{status: 202}}
    end)

    assert request() |> put_req_header("cf-ray", "a3e837c27a56c4cf-SEA") |> call() |> Map.fetch!(:status) == 202
  end

  test "refuses cross-origin, malformed, compressed and oversized requests before forwarding" do
    for {conn, status} <- [
          {request() |> delete_req_header("sec-fetch-site") |> put_req_header("origin", "https://evil.example"), 403},
          {request("not-json"), 400},
          {request("[]"), 400},
          {put_req_header(request(), "content-encoding", "gzip"), 415},
          {request(String.duplicate("x", 262_145)), 413}
        ] do
      assert call(conn).status == status
    end
  end

  test "does not acknowledge failed or timed-out forwarding as successful ingestion" do
    for result <- [{:ok, %Req.Response{status: 429}}, {:ok, %Req.Response{status: 500}}, {:error, :timeout}] do
      expect(Req, :post, fn @receiver, _options -> result end)
      assert call(request()).status == 503
    end
  end

  test "leaves other routes alone and disables an unconfigured collector" do
    conn = conn(:get, "/users/log_in")
    assert call(conn) == conn
    assert request() |> Map.put(:method, "GET") |> call() |> Map.fetch!(:status) == 405

    stub(Environment, :faro_receiver_url, fn -> nil end)
    assert call(request()).status == 404
  end
end
