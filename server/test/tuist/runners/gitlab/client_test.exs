defmodule Tuist.Runners.GitLab.ClientTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Runners.GitLab.Client
  alias Tuist.Runners.GitLab.Connection

  defmodule Coordinator do
    @moduledoc false
    @behaviour Plug

    def init(owner), do: owner

    def call(conn, owner) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:coordinator_request, conn.method, conn.request_path, body, conn.req_headers})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> respond()
    end

    defp respond(%{method: "PUT"} = conn), do: Plug.Conn.send_resp(conn, 200, JSON.encode!("200"))
    defp respond(conn), do: Plug.Conn.send_resp(conn, 201, JSON.encode!(%{id: 42, token: "job-local-test"}))
  end

  setup :verify_on_exit!

  test "writes a routing error to the job trace before failing the job" do
    payload = %{"id" => 42, "token" => "job-secret"}
    expect(SSRFGuard, :pin, 2, fn url -> {:ok, url, "gitlab.com"} end)

    expect(Req, :request, fn opts ->
      assert opts[:method] == :patch
      assert opts[:url] == "https://gitlab.com/api/v4/jobs/42/trace"
      assert opts[:body] == "Tuist: Invalid job tags\n"
      assert {"job-token", "job-secret"} in opts[:headers]
      assert {"content-range", "0-23"} in opts[:headers]
      {:ok, %{status: 202}}
    end)

    expect(Req, :request, fn opts ->
      assert opts[:method] == :put
      assert opts[:json].state == "failed"
      assert opts[:json].failure_reason == "script_failure"
      {:ok, %{status: 200}}
    end)

    assert {:ok, nil} = Client.reject_job("https://gitlab.com", payload, "Invalid job tags")
  end

  test "retries a rejected job update when the trace was already accepted" do
    expect(SSRFGuard, :pin, 2, fn url -> {:ok, url, "gitlab.com"} end)

    expect(Req, :request, fn opts ->
      assert opts[:method] == :patch
      {:ok, %{status: 416}}
    end)

    expect(Req, :request, fn opts ->
      assert opts[:method] == :put
      {:ok, %{status: 200}}
    end)

    assert {:ok, nil} =
             Client.reject_job("https://gitlab.com", %{"id" => 42, "token" => "job-secret"}, "Invalid job tags")
  end

  test "pins public DNS, disables redirects and never retries an acquisition" do
    connection = %Connection{id: 7, url: "https://gitlab.example.com", runner_token: "glrt-secret"}

    expect(SSRFGuard, :pin, fn "https://gitlab.example.com/api/v4/jobs/request" ->
      {:ok, "https://1.1.1.1/api/v4/jobs/request", "gitlab.example.com"}
    end)

    expect(Req, :request, fn opts ->
      assert opts[:url] == "https://1.1.1.1/api/v4/jobs/request"
      assert opts[:retry] == false
      assert opts[:redirect] == false
      assert opts[:json].token == "glrt-secret"
      assert opts[:json].info.executor == "shell"
      refute Map.get(opts[:json].info.features, :image, false)
      {:ok, %{status: 204}}
    end)

    assert {:ok, nil} = Client.request_job(connection)
  end

  test "refuses private instance addresses before sending credentials" do
    reject(&Req.request/1)
    connection = %Connection{id: 1, url: "https://127.0.0.1", runner_token: "glrt-secret"}
    assert {:error, :private_ip_resolved} = Client.request_job(connection)
  end

  test "uses only the job token for status updates and recognizes cancellation" do
    expect(SSRFGuard, :pin, fn _ -> {:ok, "https://1.1.1.1/api/v4/jobs/42", "gitlab.com"} end)

    expect(Req, :request, fn opts ->
      assert opts[:json].token == "job-token"
      assert {"job-token", "job-token"} in opts[:headers]
      {:ok, %{status: 200, headers: %{"job-status" => ["canceling"]}, body: %{}}}
    end)

    assert {:error, :cancelled} =
             Client.update_job("https://gitlab.com", %{"id" => 42, "token" => "job-token"}, "running", nil)
  end

  test "recognizes cancellation even when the coordinator rejects further updates" do
    expect(SSRFGuard, :pin, fn url -> {:ok, url, "gitlab.com"} end)
    expect(Req, :request, fn _ -> {:ok, %{status: 403, headers: %{"job-status" => ["canceled"]}}} end)

    assert {:error, :cancelled} =
             Client.update_job("https://gitlab.com", %{"id" => 42, "token" => "job-token"}, "running", nil)
  end

  test "accepts the scalar JSON response returned by real coordinator keepalives" do
    server = start_supervised!({Bandit, plug: {Coordinator, self()}, port: 0, ip: :loopback, startup_log: false})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    expect(SSRFGuard, :connect_options, fn "127.0.0.1" -> [] end)

    expect(SSRFGuard, :pin, fn "https://gitlab.example.com/api/v4/jobs/42" ->
      {:ok, "http://127.0.0.1:#{port}/api/v4/jobs/42", "127.0.0.1"}
    end)

    assert {:ok, nil} =
             Client.update_job("https://gitlab.example.com", %{"id" => 42, "token" => "job-local-test"}, "running", nil)

    assert_receive {:coordinator_request, "PUT", "/api/v4/jobs/42", body, headers}
    assert JSON.decode!(body)["state"] == "running"
    assert {"job-token", "job-local-test"} in headers
  end

  test "bounds response bytes and disables implicit decompression" do
    connection = %Connection{id: 1, url: "https://gitlab.com", runner_token: "glrt-secret"}
    expect(SSRFGuard, :pin, fn url -> {:ok, url, "gitlab.com"} end)

    expect(Req, :request, fn opts ->
      assert opts[:raw]
      response = %Req.Response{status: 201, body: String.duplicate("x", 16 * 1024 * 1024)}
      assert {:halt, {:request, %{status: 413, body: ""}}} = opts[:into].({:data, "x"}, {:request, response})
      {:ok, %{status: 413}}
    end)

    assert {:error, {:http_status, 413}} = Client.request_job(connection)
  end

  test "streams and decodes a real local coordinator assignment" do
    server = start_supervised!({Bandit, plug: {Coordinator, self()}, port: 0, ip: :loopback, startup_log: false})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    expect(SSRFGuard, :connect_options, fn "127.0.0.1" -> [] end)

    expect(SSRFGuard, :pin, fn "https://gitlab.example.com/api/v4/jobs/request" ->
      {:ok, "http://127.0.0.1:#{port}/api/v4/jobs/request", "127.0.0.1"}
    end)

    connection = %Connection{id: 1, url: "https://gitlab.example.com", runner_token: "glrt-local-test"}
    assert {:ok, %{"id" => 42, "token" => "job-local-test"}} = Client.request_job(connection)
    assert_receive {:coordinator_request, "POST", "/api/v4/jobs/request", body, headers}
    assert JSON.decode!(body)["token"] == "glrt-local-test"
    assert {"runner-token", "glrt-local-test"} in headers
  end
end
