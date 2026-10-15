defmodule TuistWeb.RateLimit.CallerPolicyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.User
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit

  defmodule HeadersAdapter do
    @moduledoc false
    def get_headers(headers), do: headers
  end

  test "dashboard checks and authenticated MCP explicitly select the local allowance" do
    conn = %{
      Plug.Test.conn(:get, "/account/project")
      | path_params: %{"account_handle" => "account", "project_handle" => "project"}
    }

    owner = self()
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    stub(Authentication, :current_user, fn _ -> nil end)
    stub(Authentication, :authenticated_subject, fn _ -> %User{id: 123} end)

    stub(RateLimit, :hit, fn key, opts ->
      send(owner, {:policy, key, opts[:failure_policy]})
      {:allow, 1}
    end)

    assert ^conn = RateLimit.rate_limit(conn, %{})
    assert_receive {:policy, "dashboard:GET:" <> _, :local}
    assert_receive {:policy, "dashboard:anon-scope:GET:account/project", :local}
    assert {:allow, 1} = RateLimit.MCP.hit(conn)
    assert_receive {:policy, "mcp:auth:user:123", :local}
    refute_received {:policy, _, _}
  end

  test "Once keeps its pre-authentication guard on the deny policy" do
    owner = self()

    stub(RateLimit, :hit, fn key, opts ->
      send(owner, {:policy, key, Keyword.get(opts, :failure_policy, :deny)})
      {:deny, 1}
    end)

    stream = %GRPC.Server.Stream{adapter: HeadersAdapter, payload: %{"x-forwarded-for" => "127.0.0.1"}}

    assert {:error, %GRPC.RPCError{}} =
             RateLimit.OnceEvents.call(%{}, stream, fn _, _ -> send(owner, :service_called) end, [])

    assert_receive {:policy, "once-events:127.0.0.1", :deny}
    refute_received :service_called
  end

  test "callers outside the availability allowlist retain fail-closed policy" do
    conn = Plug.Test.conn(:get, "/")
    owner = self()
    stub(Authentication, :authenticated_subject, fn _ -> %User{id: 123} end)

    stub(RateLimit, :hit, fn key, opts ->
      send(owner, {:policy, key, Keyword.get(opts, :failure_policy, :deny)})
      {:deny, 1}
    end)

    calls = [
      {"auth:", fn -> RateLimit.Auth.hit(conn) end},
      {"agent_auth:ip:", fn -> RateLimit.AgentAuth.hit(conn) end},
      {"agent_auth:registration:", fn -> RateLimit.AgentAuth.hit_registration(conn, :anonymous) end},
      {"registration:", fn -> RateLimit.Registration.hit("session") end},
      {"atlas:", fn -> RateLimit.Atlas.hit(conn) end},
      {"authorization-denied:", fn -> RateLimit.Authorization.hit(conn) end},
      {"metrics:", fn -> RateLimit.Metrics.hit(conn) end},
      {"scim:", fn -> RateLimit.SCIM.hit(conn) end}
    ]

    for {prefix, call} <- calls do
      assert {:deny, 1} = call.()
      assert_receive {:policy, key, :deny}
      assert String.starts_with?(key, prefix)
    end

    refute_receive {:policy, _, _}
  end
end
