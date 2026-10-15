defmodule TuistWeb.RateLimit.CallerPolicyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.User
  alias TuistWeb.Authentication
  alias TuistWeb.RateLimit

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
