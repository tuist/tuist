defmodule AtlasWeb.SupportAgentFeedbackControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Repo
  alias Atlas.Support
  alias Atlas.Support.Thread

  @body %{
    "name" => "Maya Chen",
    "email" => "maya@customer.example",
    "body" => "Expected: test runs filtered by branch\n\nActual: the branch was ignored",
    "context" => %{"tool_name" => "list_test_runs", "category" => "missing_data"}
  }

  setup :verify_on_exit!

  setup do
    signer = JOSE.JWK.generate_key({:rsa, 2048})
    public = signer |> JOSE.JWK.to_public() |> JOSE.JWK.to_map() |> elem(1) |> Map.put("kid", "product-key")

    policy = %{
      issuer: "https://kubernetes.default.svc.cluster.local",
      audience: "atlas-support-ingest",
      jwks: JSON.encode!(%{"keys" => [public]}),
      subject: "product:product-server"
    }

    stub(Support, :ingest_workload_identity_policy, fn -> policy end)
    %{token: workload_token(signer, "product", "product-server")}
  end

  test "opens a support conversation for an authenticated report", %{conn: conn, token: token} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/api/support/agent-feedback", @body)

    assert %{"id" => id} = json_response(conn, 201)
    thread = Repo.get!(Thread, id)
    assert thread.customer_email == "maya@customer.example"
    assert thread.metadata["channel"] == "agent_feedback"
  end

  test "rejects a token signed by a key outside the pinned JWKS", %{conn: conn} do
    token = workload_token(JOSE.JWK.generate_key({:rsa, 2048}), "product", "product-server")

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/api/support/agent-feedback", @body)

    assert %{"error" => "invalid token"} = json_response(conn, 401)
    assert Repo.aggregate(Thread, :count) == 0
  end

  test "stays closed when no workload identity is configured", %{conn: conn, token: token} do
    stub(Support, :ingest_workload_identity_policy, fn -> %{} end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/api/support/agent-feedback", @body)

    assert %{"error" => "not configured"} = json_response(conn, 503)
    assert Repo.aggregate(Thread, :count) == 0
  end

  test "limits how many reports one user's agents can open", %{conn: conn, token: token} do
    body = Map.put(@body, "email", "looping-#{System.unique_integer([:positive])}@customer.example")

    statuses =
      for _attempt <- 1..11 do
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> post(~p"/api/support/agent-feedback", body)
        |> Map.fetch!(:status)
      end

    assert Enum.count(statuses, &(&1 == 201)) == 10
    assert List.last(statuses) == 429
  end

  test "caps reports from all users together", %{conn: conn, token: token} do
    stub(Atlas.RateLimit, :hit, fn
      "support_agent_feedback:overall", _scale, _limit -> {:deny, 30_000}
      _key, _scale, _limit -> {:allow, 1}
    end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/api/support/agent-feedback", @body)

    assert json_response(conn, 429)
    assert get_resp_header(conn, "retry-after") == ["30"]
    assert Repo.aggregate(Thread, :count) == 0
  end

  test "rejects a report without an email", %{conn: conn, token: token} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/api/support/agent-feedback", Map.delete(@body, "email"))

    assert %{"error" => "email_required"} = json_response(conn, 422)
  end

  defp workload_token(signer, namespace, service_account) do
    now = System.os_time(:second)

    claims = %{
      "iss" => "https://kubernetes.default.svc.cluster.local",
      "aud" => ["atlas-support-ingest"],
      "sub" => "system:serviceaccount:#{namespace}:#{service_account}",
      "iat" => now,
      "nbf" => now,
      "exp" => now + 3600,
      "kubernetes.io" => %{
        "namespace" => namespace,
        "serviceaccount" => %{"name" => service_account, "uid" => "uid"},
        "pod" => %{"name" => "server-pod", "uid" => "pod-uid"}
      }
    }

    signer
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "product-key"}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end
end
