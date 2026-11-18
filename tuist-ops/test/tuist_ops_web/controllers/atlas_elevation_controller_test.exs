defmodule TuistOpsWeb.AtlasElevationControllerTest do
  use TuistOpsWeb.ConnCase, async: true
  use Mimic

  alias TuistOps.Environment
  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.SlackClient
  alias TuistOps.JIT.TailscaleClient
  alias TuistOps.Repo

  setup :verify_on_exit!

  @email "marek@tuist.dev"
  @thread "T-01a1a59e-55fb-744b-9415-b85a337f24d2"
  @atlas "system:serviceaccount:atlas-production:atlas"
  @body %{
    "email" => @email,
    "env" => "canary",
    "thread_id" => @thread,
    "intent" => "Uncordon the canary runners-linux host",
    "ttl_seconds" => 1800,
    "approval_id" => "8c7a4c1e-4a43-4c1b-9d0e-2f1f4d2c9b10"
  }

  setup do
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, public} = JOSE.JWK.to_public_map(key)
    jwks = JSON.encode!(%{"keys" => [Map.put(public, "kid", "atlas-key")]})

    stub(Environment, :atlas_token_jwks, fn -> jwks end)

    stub(TailscaleClient, :user_role, fn
      @email -> {:ok, :owner}
      _ -> {:error, :not_found}
    end)

    reject(&SlackClient.post_message/2)
    reject(&SlackClient.update_message/3)

    %{key: key}
  end

  defp token(key, overrides \\ %{}) do
    now = System.system_time(:second)

    claims =
      Map.merge(
        %{
          "iss" => "https://kubernetes.default.svc.cluster.local",
          "aud" => ["ops.tuist.dev"],
          "sub" => @atlas,
          "iat" => now,
          "exp" => now + 3600
        },
        overrides
      )

    key
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "atlas-key"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp post_elevation(conn, token, body \\ @body) do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/atlas/elevations", JSON.encode!(body))
  end

  defp canary_orb_groups(email) do
    build_conn()
    |> put_req_header("x-tuist-amp-email", email)
    |> put_req_header("x-tuist-amp-thread-id", @thread)
    |> Map.put(:host, "kube-orb-canary.tuist.dev")
    |> get("/api/v1/policy")
    |> get_resp_header("impersonate-group")
  end

  test "an Atlas-approved call elevates exactly that thread, without Slack", %{
    conn: conn,
    key: key
  } do
    refute "tuist-canary-write" in canary_orb_groups(@email)

    conn = post_elevation(conn, token(key))

    assert %{"thread_id" => @thread, "env" => "canary", "expires_at" => expires_at} =
             json_response(conn, 201)

    {:ok, expires_at, _} = DateTime.from_iso8601(expires_at)
    assert DateTime.diff(expires_at, DateTime.utc_now()) in 1790..1800

    assert "tuist-canary-write" in canary_orb_groups(@email)
    assert [%Elevation{orb_thread_id: @thread}] = Repo.all(Elevation)
  end

  test "an approval grants once", %{conn: conn, key: key} do
    assert json_response(post_elevation(conn, token(key)), 201)
    assert json_response(post_elevation(build_conn(), token(key)), 409)
    assert Repo.aggregate(Elevation, :count) == 1
  end

  test "rejects a token Atlas minted for another audience", %{conn: conn, key: key} do
    conn = post_elevation(conn, token(key, %{"aud" => ["tuist-server"]}))
    assert json_response(conn, 401)
    assert Repo.aggregate(Elevation, :count) == 0
  end

  test "rejects a token signed by a key that is not pinned", %{conn: conn} do
    conn = post_elevation(conn, token(JOSE.JWK.generate_key({:rsa, 2048})))
    assert json_response(conn, 401)
    assert Repo.aggregate(Elevation, :count) == 0
  end

  test "rejects another ServiceAccount from the Atlas cluster", %{conn: conn, key: key} do
    conn =
      post_elevation(
        conn,
        token(key, %{"sub" => "system:serviceaccount:atlas-production:condukt-agent"})
      )

    assert json_response(conn, 401)
  end

  test "requires an engineering tailnet role for the approving person", %{conn: conn, key: key} do
    conn = post_elevation(conn, token(key), %{@body | "email" => "someone@example.com"})
    assert json_response(conn, 403)
    assert Repo.aggregate(Elevation, :count) == 0
  end

  test "refuses staging, which needs no elevation", %{conn: conn, key: key} do
    conn = post_elevation(conn, token(key), %{@body | "env" => "staging"})
    assert json_response(conn, 422)
  end
end
