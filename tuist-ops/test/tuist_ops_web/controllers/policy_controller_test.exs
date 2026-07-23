defmodule TuistOpsWeb.PolicyControllerTest do
  @moduledoc """
  Pins the contract every kubectl call depends on:

    GET /api/v1/policy
      Host: kube-<env>.tuist.dev
      X-Pomerium-Claim-Email: <user>

    → 200 OK
      Impersonate-User: <user>
      Impersonate-Group: <base tier>
      Impersonate-Group: <env write group>   (only if active elevation)

    OR

    → 403 <reason>

  The sidecar (kube-impersonator) calls this endpoint per kubectl
  request and copies the response headers onto the upstream
  apiserver request. A regression here directly mis-impersonates
  every kubectl call against every env.
  """

  use TuistOpsWeb.ConnCase, async: true
  use Mimic

  alias TuistOps.Repo
  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Request
  alias TuistOps.JIT.TailscaleClient

  setup :verify_on_exit!

  @owner "marek@tuist.dev"
  @admin "pedro@tuist.dev"
  @member "eduardo@tuist.dev"

  defp stub_role(email, role) do
    stub(TailscaleClient, :user_role, fn
      ^email -> {:ok, role}
      _ -> {:error, :not_found}
    end)
  end

  defp policy_get(conn, host, headers) do
    headers
    |> Enum.reduce(conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    |> put_req_header("x-forwarded-host", host)
    |> Map.put(:host, host)
    |> get("/api/v1/policy")
  end

  defp impersonate_groups(conn), do: get_resp_header(conn, "impersonate-group")
  defp impersonate_user(conn), do: get_resp_header(conn, "impersonate-user") |> List.first()

  defp insert_active_elevation!(email, group, opts \\ []) do
    expires_at =
      opts
      |> Keyword.get(:expires_at, DateTime.add(DateTime.utc_now(), 600, :second))
      |> DateTime.truncate(:second)

    request =
      %Request{
        requester_email: email,
        requester_slack_id: "U_TEST",
        target_group: group,
        intent: "policy controller test",
        ttl_seconds: 600,
        slack_channel_id: "C_TEST",
        expires_at: expires_at,
        status: "approved"
      }
      |> Repo.insert!()

    %Elevation{
      request_id: request.id,
      requester_email: email,
      target_group: group,
      status: "active",
      expires_at: expires_at
    }
    |> Repo.insert!()
  end

  describe "host header → env mapping" do
    setup do
      stub_role(@owner, :owner)
      :ok
    end

    test "kube-staging.tuist.dev → staging context", %{conn: conn} do
      conn = policy_get(conn, "kube-staging.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert conn.status == 200
    end

    test "kube-canary.tuist.dev → canary context", %{conn: conn} do
      conn = policy_get(conn, "kube-canary.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert conn.status == 200
    end

    test "kube-prod.tuist.dev → production context", %{conn: conn} do
      conn = policy_get(conn, "kube-prod.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert conn.status == 200
    end

    test "kube-production.tuist.dev → production context (alias)", %{conn: conn} do
      conn = policy_get(conn, "kube-production.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert conn.status == 200
    end

    test "unrecognised host → 403", %{conn: conn} do
      conn = policy_get(conn, "kube-mystery.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert conn.status == 403
      assert conn.resp_body =~ "unrecognized host"
    end
  end

  describe "subject extraction" do
    setup do
      stub_role(@owner, :owner)
      :ok
    end

    test "missing x-pomerium-claim-email → 403", %{conn: conn} do
      conn = policy_get(conn, "kube-staging.tuist.dev", [])
      assert conn.status == 403
      assert conn.resp_body =~ "no x-pomerium-claim-email"
    end

    test "empty x-pomerium-claim-email → 403", %{conn: conn} do
      conn = policy_get(conn, "kube-staging.tuist.dev", [{"x-pomerium-claim-email", ""}])
      assert conn.status == 403
      assert conn.resp_body =~ "no x-pomerium-claim-email"
    end
  end

  describe "tier resolution — no active elevation" do
    test "Owner → tuist-admins on every env", %{conn: conn} do
      stub_role(@owner, :owner)

      for host <- ~w(kube-staging.tuist.dev kube-canary.tuist.dev kube-prod.tuist.dev) do
        c = policy_get(conn, host, [{"x-pomerium-claim-email", @owner}])
        assert c.status == 200
        assert impersonate_user(c) == @owner
        assert impersonate_groups(c) == ["tuist-admins"]
      end
    end

    test "Admin → tuist-admins on every env", %{conn: conn} do
      stub_role(@admin, :admin)

      c = policy_get(conn, "kube-prod.tuist.dev", [{"x-pomerium-claim-email", @admin}])
      assert c.status == 200
      assert impersonate_user(c) == @admin
      assert impersonate_groups(c) == ["tuist-admins"]
    end

    test "Member → tuist-eng on every env", %{conn: conn} do
      stub_role(@member, :member)

      for host <- ~w(kube-staging.tuist.dev kube-canary.tuist.dev kube-prod.tuist.dev) do
        c = policy_get(conn, host, [{"x-pomerium-claim-email", @member}])
        assert c.status == 200
        assert impersonate_user(c) == @member
        assert impersonate_groups(c) == ["tuist-eng"]
      end
    end

    test "off-tailnet → 403", %{conn: conn} do
      stub(TailscaleClient, :user_role, fn _ -> {:error, :not_found} end)

      c = policy_get(conn, "kube-staging.tuist.dev", [{"x-pomerium-claim-email", "x@y.com"}])
      assert c.status == 403
      assert c.resp_body =~ "not on tailnet"
    end

    test ":unknown role → 403 (the P4 contract — unknown deny, not silently :member)",
         %{conn: conn} do
      stub_role(@member, :unknown)

      c = policy_get(conn, "kube-staging.tuist.dev", [{"x-pomerium-claim-email", @member}])
      assert c.status == 403
      assert c.resp_body =~ "no cluster access tier"
    end

    test "tailnet lookup error → 403", %{conn: conn} do
      stub(TailscaleClient, :user_role, fn _ -> {:error, :timeout} end)

      c = policy_get(conn, "kube-staging.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert c.status == 403
      assert c.resp_body =~ "tailnet lookup failed"
    end
  end

  describe "tier resolution — active elevation" do
    test "Owner + active staging elevation → tuist-admins + tuist-staging-write",
         %{conn: conn} do
      stub_role(@owner, :owner)
      insert_active_elevation!(@owner, "group:tuist-staging-write")

      c = policy_get(conn, "kube-staging.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert c.status == 200
      assert impersonate_user(c) == @owner
      assert impersonate_groups(c) == ["tuist-admins", "tuist-staging-write"]
    end

    test "Member + active canary elevation → tuist-eng + tuist-canary-write",
         %{conn: conn} do
      stub_role(@member, :member)
      insert_active_elevation!(@member, "group:tuist-canary-write")

      c = policy_get(conn, "kube-canary.tuist.dev", [{"x-pomerium-claim-email", @member}])
      assert c.status == 200
      assert impersonate_groups(c) == ["tuist-eng", "tuist-canary-write"]
    end

    test "Member + active PROD elevation → tuist-eng + tuist-production-write",
         %{conn: conn} do
      stub_role(@member, :member)
      insert_active_elevation!(@member, "group:tuist-production-write")

      c = policy_get(conn, "kube-prod.tuist.dev", [{"x-pomerium-claim-email", @member}])
      assert c.status == 200
      assert impersonate_groups(c) == ["tuist-eng", "tuist-production-write"]
    end

    test "elevation for wrong env is ignored (staging elevation, prod call)", %{conn: conn} do
      stub_role(@owner, :owner)
      insert_active_elevation!(@owner, "group:tuist-staging-write")

      c = policy_get(conn, "kube-prod.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert c.status == 200
      assert impersonate_groups(c) == ["tuist-admins"]
    end

    test "expired elevation row is ignored even if status is still active", %{conn: conn} do
      stub_role(@owner, :owner)

      insert_active_elevation!(@owner, "group:tuist-staging-write",
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      )

      c = policy_get(conn, "kube-staging.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert c.status == 200
      assert impersonate_groups(c) == ["tuist-admins"]
    end

    test "elevation for a different user is ignored", %{conn: conn} do
      stub_role(@owner, :owner)
      insert_active_elevation!(@admin, "group:tuist-staging-write")

      c = policy_get(conn, "kube-staging.tuist.dev", [{"x-pomerium-claim-email", @owner}])
      assert c.status == 200
      assert impersonate_groups(c) == ["tuist-admins"]
    end
  end

  describe "sub-path handling" do
    test "GET /api/v1/policy/anything routes to the same handler", %{conn: conn} do
      stub_role(@owner, :owner)

      c =
        conn
        |> put_req_header("x-pomerium-claim-email", @owner)
        |> Map.put(:host, "kube-staging.tuist.dev")
        |> get("/api/v1/policy/api/v1/namespaces/tuist/pods")

      assert c.status == 200
      assert impersonate_user(c) == @owner
    end

    test "POST routed to evaluate too", %{conn: conn} do
      stub_role(@owner, :owner)

      c =
        conn
        |> put_req_header("x-pomerium-claim-email", @owner)
        |> put_req_header("content-type", "application/json")
        |> Map.put(:host, "kube-staging.tuist.dev")
        |> post("/api/v1/policy", "{}")

      assert c.status == 200
    end
  end
end
