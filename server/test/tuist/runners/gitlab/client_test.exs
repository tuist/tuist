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
      |> Plug.Conn.send_resp(201, JSON.encode!(%{id: 42, token: "job-local-test"}))
    end
  end

  setup :verify_on_exit!

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

    assert {:ok, nil} = Client.request_job(connection, :macos)
  end

  test "refuses private instance addresses before sending credentials" do
    reject(&Req.request/1)
    connection = %Connection{id: 1, url: "https://127.0.0.1", runner_token: "glrt-secret"}
    assert {:error, :private_ip_resolved} = Client.request_job(connection, :linux)
  end

  test "uses only the job token for status updates and recognizes cancellation" do
    expect(SSRFGuard, :pin, fn _ -> {:ok, "https://1.1.1.1/api/v4/jobs/42", "gitlab.com"} end)

    expect(Req, :request, fn opts ->
      assert opts[:json].token == "job-token"
      {:ok, %{status: 200, headers: %{"job-status" => ["canceling"]}, body: %{}}}
    end)

    assert {:error, :cancelled} =
             Client.update_job("https://gitlab.com", %{"id" => 42, "token" => "job-token"}, "running", nil)
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

    assert {:error, {:http_status, 413}} = Client.request_job(connection, :linux)
  end

  test "streams and decodes a real local coordinator assignment" do
    server = start_supervised!({Bandit, plug: {Coordinator, self()}, port: 0, ip: :loopback, startup_log: false})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    expect(SSRFGuard, :connect_options, fn "127.0.0.1" -> [] end)

    expect(SSRFGuard, :pin, fn "https://gitlab.example.com/api/v4/jobs/request" ->
      {:ok, "http://127.0.0.1:#{port}/api/v4/jobs/request", "127.0.0.1"}
    end)

    connection = %Connection{id: 1, url: "https://gitlab.example.com", runner_token: "glrt-local-test"}
    assert {:ok, %{"id" => 42, "token" => "job-local-test"}} = Client.request_job(connection, :linux)
    assert_receive {:coordinator_request, "POST", "/api/v4/jobs/request", body, headers}
    assert JSON.decode!(body)["token"] == "glrt-local-test"
    assert {"runner-token", "glrt-local-test"} in headers
  end
end
