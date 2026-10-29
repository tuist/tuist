defmodule AtlasWeb.InferenceDecisionControllerTest do
  use AtlasWeb.ConnCase, async: true

  alias Atlas.Audit.Activity
  alias Atlas.Inference
  alias Atlas.Inference.Usage
  alias Atlas.Repo

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, provider} =
      Inference.create_provider(%{
        key: "typesafe-#{suffix}",
        base_url: "https://api.typesafe.ai/v1",
        decision_path: "systemone",
        api_key: "upstream-secret"
      })

    {:ok, profile} =
      Inference.create_profile(%{
        name: "quality-#{suffix}",
        upstream_provider: provider.key,
        upstream_model: "jev-latest",
        input_cost_per_million: "0.042",
        output_cost_per_million: "0"
      })

    {:ok, {token, value}} = Inference.create_token(profile, %{name: "review"})
    %{profile: profile, token: token, value: value}
  end

  test "relays native decisions and records token counts and configured costs", %{
    conn: conn,
    profile: profile,
    token: token,
    value: value
  } do
    body = %{
      "model" => profile.name,
      "state" => %{"diff" => "+new"},
      "questions" => %{"safe" => %{"type" => "noul", "instructions" => "Is this safe?"}}
    }

    response = %{
      "model" => "jev-1.13.0",
      "answers" => %{"safe" => %{"type" => "noul", "noul" => 0.9}},
      "usage" => %{"input_tokens" => 1_000, "output_tokens" => 20}
    }

    Inference.put_process_config(
      request: fn request ->
        assert request[:retry] == false
        assert request[:url] == "https://api.typesafe.ai/v1/systemone"
        assert {"authorization", "Bearer upstream-secret"} in request[:headers]
        assert request[:json] == Map.put(body, "model", "jev-latest")
        {:ok, %{status: 200, headers: [], body: response}}
      end
    )

    conn = conn |> put_req_header("authorization", "Bearer " <> value) |> post("/inference/v1/systemone", body)
    assert json_response(conn, 200) == response
    usage = Repo.get_by!(Usage, token_id: token.id)
    assert usage.operation == "decision"
    assert usage.input_tokens == 1_000
    assert usage.output_tokens == 20
    assert usage.total_tokens == 1_020
    assert Decimal.equal?(usage.cost_usd, Decimal.new("0.000042"))
    now = DateTime.utc_now()
    summary = Inference.usage_summary(token, {DateTime.add(now, -60), DateTime.add(now, 60)})
    activity = Repo.get_by!(Activity, action: "inference.relayed", target_id: profile.id)
    assert activity.interface == "api"
    assert activity.metadata["operation"] == "decision"
    assert activity.metadata["usage_reported"] == true
    assert activity.metadata["token_id"] == token.id
    assert activity.metadata["path"] == "/admin/inference/profiles/#{profile.id}"
    refute Map.has_key?(activity.metadata, "state")
    assert summary.request_count == 1
    assert summary.input_tokens == 1_000
    assert Decimal.equal?(summary.cost_usd, usage.cost_usd)
  end

  test "rejects missing credentials, model overrides and streaming without contacting the provider", %{
    profile: profile,
    value: value
  } do
    Inference.put_process_config(request: fn _request -> flunk("unexpected upstream request") end)
    assert build_conn() |> post("/inference/v1/decisions", %{"model" => profile.name}) |> json_response(401)

    for {body, status} <- [
          {%{}, 400},
          {%{"model" => "other"}, 403},
          {%{"model" => profile.name, "stream" => true}, 400}
        ] do
      conn =
        build_conn() |> put_req_header("authorization", "Bearer " <> value) |> post("/inference/v1/decisions", body)

      assert json_response(conn, status)["error"]
    end
  end

  test "upstream errors are forwarded once and have no billable usage", %{
    conn: conn,
    profile: profile,
    token: token,
    value: value
  } do
    Inference.put_process_config(
      request: fn _request ->
        send(self(), :upstream_called)

        {:ok,
         %{
           status: 400,
           headers: [],
           body: %{"error" => %{"code" => "streaming_required"}, "usage" => %{"input_tokens" => 1_000}}
         }}
      end
    )

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> value)
      |> post("/inference/v1/decisions", %{"model" => profile.name})

    assert json_response(conn, 400)["error"]["code"] == "streaming_required"
    assert_received :upstream_called
    refute_received :upstream_called
    usage = Repo.get_by!(Usage, token_id: token.id)
    assert usage.input_tokens == 0
    assert Decimal.equal?(usage.cost_usd, 0)
  end

  test "missing decision usage is flagged without discarding the provider response", %{
    profile: profile,
    token: token,
    value: value
  } do
    response = %{"answers" => %{}}
    Inference.put_process_config(request: fn _request -> {:ok, %{status: 200, body: response, headers: []}} end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        conn =
          build_conn()
          |> put_req_header("authorization", "Bearer " <> value)
          |> post("/inference/v1/decisions", %{"model" => profile.name})

        assert json_response(conn, 200) == response
      end)

    assert log =~ "cost is unknown"
    usage = Repo.get_by!(Usage, token_id: token.id)
    assert usage.input_tokens == 0
    activity = Repo.get_by!(Activity, action: "inference.relayed", target_id: profile.id)
    assert activity.metadata["usage_reported"] == false

    for payload <- [
          %{},
          %{"input_tokens" => -1, "output_tokens" => 0},
          %{"input_tokens" => "invalid", "output_tokens" => 0}
        ] do
      refute Inference.decision_usage_reported?(%{body: %{"usage" => payload}})
    end

    assert Inference.decision_usage_reported?(%{body: %{"usage" => %{"input_tokens" => 0, "output_tokens" => "0"}}})
  end

  test "Atlas role tokens cannot bypass their operation limits through decisions", %{profile: profile} do
    {:ok, profile} =
      Inference.update_profile(profile, %{atlas_inference: true, atlas_coding: true, atlas_embedding: true})

    Inference.put_process_config(request: fn _request -> flunk("unexpected upstream request") end)

    for role <- [:inference, :coding, :embedding] do
      {:ok, {_token, value}} = Inference.ensure_atlas_token(profile, role)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> value)
        |> post("/inference/v1/decisions", %{"model" => profile.name})

      assert json_response(conn, 403)["error"]["message"] == "Decision requests require a dedicated profile token."
    end
  end

  test "revoked and expired tokens cannot make decision requests", %{profile: profile, token: token, value: value} do
    {:ok, _token} = Inference.revoke_token(token)

    {:ok, {_token, expired}} =
      Inference.create_token(profile, %{name: "expired", expires_at: DateTime.add(DateTime.utc_now(), -60)})

    Inference.put_process_config(request: fn _request -> flunk("unexpected upstream request") end)

    for credential <- [value, expired] do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> credential)
        |> post("/inference/v1/systemone", %{"model" => profile.name})

      assert json_response(conn, 401)["error"]
    end
  end

  test "chat and embedding routes keep their paths and accounting", %{profile: profile, value: value, token: token} do
    for {path, upstream_path, operation} <- [
          {"chat/completions", "chat/completions", "chat_completion"},
          {"embeddings", "embeddings", "embedding"}
        ] do
      Inference.put_process_config(
        request: fn request ->
          assert request[:url] == "https://api.typesafe.ai/v1/" <> upstream_path
          {:ok, %{status: 200, headers: [], body: %{"usage" => %{"input_tokens" => 100, "output_tokens" => 0}}}}
        end
      )

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> value)
        |> post("/inference/v1/" <> path, %{"model" => profile.name})

      assert json_response(conn, 200)["usage"]["input_tokens"] == 100
      assert Repo.get_by(Usage, token_id: token.id, operation: operation)
    end
  end

  test "transport failures return a sanitized error", %{conn: conn, profile: profile, value: value} do
    Inference.put_process_config(request: fn _request -> {:error, :closed} end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> value)
      |> post("/inference/v1/decisions", %{"model" => profile.name})

    assert json_response(conn, 502)["error"]["message"] == "The upstream provider request failed."
  end

  test "chat providers require an explicit decision path", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    {:ok, provider} = Inference.create_provider(%{key: "chat-#{suffix}", base_url: "https://api.openai.com/v1"})

    {:ok, profile} =
      Inference.create_profile(%{name: "chat-#{suffix}", upstream_provider: provider.key, upstream_model: "example"})

    {:ok, {_token, value}} = Inference.create_token(profile, %{name: "chat"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> value)
      |> post("/inference/v1/decisions", %{"model" => profile.name})

    assert json_response(conn, 400)["error"]["message"] == "The provider has no decision endpoint configured."
  end
end
