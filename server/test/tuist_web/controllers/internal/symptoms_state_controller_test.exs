defmodule TuistWeb.Internal.SymptomsStateControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client
  alias Tuist.Pulse.Investigations
  alias Tuist.Pulse.Symptoms
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.PulseFixtures

  @id "0193a1f0-0000-7000-8000-00000000000a"

  setup do
    user = AccountsFixtures.user_fixture()
    account = AccountsFixtures.organization_fixture(creator: user).account
    stub(Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)

    {:ok, _} =
      PulseFixtures.mirror_symptoms(account, [PulseFixtures.symptom_revision(%{"symptom_id" => @id, "tier" => "audit"})])

    stub(Environment, :symptoms_config, fn ->
      [evaluator_namespace: "tuist-symptoms", evaluator_service_account: "symptoms-evaluator"]
    end)

    # The apiserver authenticates a token only for the audience it was minted for.
    stub(Client, :create_bound_token_review, fn
      "evaluator-token", "tuist-symptoms-state", _opts ->
        {:ok, %{username: "system:serviceaccount:tuist-symptoms:symptoms-evaluator", uid: "uid", extra: %{}}}

      "other-workload", "tuist-symptoms-state", _opts ->
        {:ok, %{username: "system:serviceaccount:tuist:tuist-server", uid: "uid", extra: %{}}}

      _token, _audience, _opts ->
        {:error, :unauthenticated}
    end)

    %{user: user, account: account}
  end

  defp request(conn, token, query \\ "") do
    conn = if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn
    get(conn, "/api/internal/symptoms/state" <> query)
  end

  test "returns human state after the cursor to the evaluator", %{conn: conn, user: user, account: account} do
    :ok = Symptoms.ack(user, account, @id)
    :ok = Symptoms.mute(user, account, @id, "latency", DateTime.add(DateTime.utc_now(), 3600))

    body = conn |> request("evaluator-token") |> json_response(200)

    assert %{
             "acks" => [%{"symptom_id" => @id, "revision" => 1}],
             "mutes" => [%{"phenomenon" => "latency", "entity" => %{"key" => "POST /api/runs"}}],
             "investigations" => [],
             "outcomes" => [],
             "next" => next
           } = body

    assert %{"acks" => [], "mutes" => [], "next" => ^next} =
             build_conn() |> request("evaluator-token", "?after=#{next}") |> json_response(200)

    assert build_conn() |> request("evaluator-token") |> get_resp_header("cache-control") == ["no-store"]
  end

  test "returns pending investigations without generated briefs or steps", %{conn: conn, user: user, account: account} do
    {:ok, _investigation} = Investigations.request_brief(user, account, @id)

    body = conn |> request("evaluator-token") |> json_response(200)

    assert %{
             "investigations" => [
               %{
                 "symptom_id" => @id,
                 "trigger" => "person",
                 "brief_id" => nil,
                 "brief_revision" => nil,
                 "steps_taken" => [],
                 "reverted" => false,
                 "change_seq" => change_seq
               }
             ],
             "next" => change_seq
           } = body

    assert %{"investigations" => []} =
             build_conn() |> request("evaluator-token", "?after=#{change_seq}") |> json_response(200)
  end

  test "accepts only the evaluator's ServiceAccount", %{conn: conn} do
    assert %{"error" => "unauthenticated"} = conn |> request(nil) |> json_response(401)
    assert %{"error" => "unauthenticated"} = build_conn() |> request("forged") |> json_response(401)
    assert %{"error" => "unauthenticated"} = build_conn() |> request("other-workload") |> json_response(401)
  end

  test "rejects a bad cursor after authenticating", %{conn: conn} do
    assert %{"error" => "unauthenticated"} = conn |> request(nil, "?after=x") |> json_response(401)

    for query <- ["?after=x", "?after=-1", "?after=1.5"] do
      assert %{"error" => "invalid_cursor"} = build_conn() |> request("evaluator-token", query) |> json_response(400)
    end
  end

  test "is unavailable until the evaluator is configured", %{conn: conn} do
    stub(Environment, :symptoms_config, fn -> [] end)
    reject(&Client.create_bound_token_review/3)
    assert %{"error" => "unavailable"} = conn |> request("evaluator-token") |> json_response(503)
  end
end
