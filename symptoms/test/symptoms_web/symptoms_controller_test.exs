defmodule SymptomsWeb.SymptomsControllerTest do
  use Symptoms.DataCase

  import Phoenix.ConnTest
  import Plug.Conn

  alias Symptoms.Log
  alias Symptoms.Store.Symptom

  @endpoint SymptomsWeb.Endpoint
  @at ~U[2026-11-16 10:00:00.000000Z]

  defp authed, do: put_req_header(build_conn(), "authorization", "Bearer test-api-token")

  # Three symptoms with one revision each and a second revision of the first:
  # four revisions, seq strictly increasing.
  setup do
    ids =
      for {key, tier, cost} <- [{"a", "board", 10.0}, {"b", "page", 30.0}, {"c", "board", 20.0}] do
        id = Log.uuid7(@at)

        symptom =
          Repo.insert!(%Symptom{
            id: id,
            symptom_key: key,
            root_key: "60:entity:#{key}",
            phenomenon: "request_errors",
            state: "open",
            tier: tier,
            max_tier: tier,
            expected_cost: cost,
            opened_at: @at
          })

        Repo.transaction(fn -> Log.append!(symptom, %{"tier" => tier, "transition" => "opened", "root" => nil}, @at) end)
        id
      end

    first = Repo.get!(Symptom, hd(ids))
    Repo.transaction(fn -> Log.append!(first, %{"tier" => "board", "transition" => "annotated"}, @at) end)
    %{ids: ids}
  end

  test "pages through the log with after and limit", %{ids: [a, b, c]} do
    body = authed() |> get("/api/v1/symptoms/log?after=0&limit=2") |> json_response(200)
    assert [%{"symptom_id" => ^a, "revision" => 1} = r1, %{"symptom_id" => ^b} = r2] = body["revisions"]
    assert r2["seq"] > r1["seq"]
    assert body["next"] == r2["seq"]

    body = authed() |> get("/api/v1/symptoms/log?after=#{body["next"]}&limit=2") |> json_response(200)
    assert [%{"symptom_id" => ^c}, %{"symptom_id" => ^a, "revision" => 2} = last] = body["revisions"]
    assert body["next"] == last["seq"]

    # Nothing newer: next stays at after.
    assert %{"revisions" => [], "next" => next} =
             authed() |> get("/api/v1/symptoms/log?after=#{last["seq"]}") |> json_response(200)

    assert next == last["seq"]
    assert Enum.all?([r1, r2, last], &(&1["schema_version"] == "1.0"))
  end

  test "rejects missing, wrong and malformed credentials" do
    assert %{"error" => "unauthenticated"} = build_conn() |> get("/api/v1/symptoms/log") |> json_response(401)

    assert build_conn()
           |> put_req_header("authorization", "Bearer test-api-tokem")
           |> get("/api/v1/symptoms/log")
           |> json_response(401)

    assert build_conn()
           |> put_req_header("authorization", "Basic test-api-token")
           |> get("/api/v1/symptoms/board")
           |> json_response(401)
  end

  test "append! reads the current revision under the lock, so a stale symptom never reuses one", %{ids: [a | _]} do
    # The struct loaded now has revision 2; a concurrent writer appends
    # revision 3 first. Appending from the stale struct must write 4.
    stale = Repo.get!(Symptom, a)
    Repo.transaction(fn -> Log.append!(stale, %{"tier" => "board", "transition" => "annotated"}, @at) end)

    assert {:ok, %{revision: 4}} =
             Repo.transaction(fn -> Log.append!(stale, %{"tier" => "page", "transition" => "escalated"}, @at) end)

    assert %{"revision" => 4, "tier" => "page"} = Log.latest(a)
  end

  test "rejects a malformed cursor" do
    assert %{"error" => "invalid_cursor"} = authed() |> get("/api/v1/symptoms/log?after=x") |> json_response(400)
    assert %{"error" => "invalid_limit"} = authed() |> get("/api/v1/symptoms/log?limit=0") |> json_response(400)
  end

  test "is unavailable without a configured token" do
    previous = Application.get_env(:symptoms, :api_token)
    Application.put_env(:symptoms, :api_token, nil)
    on_exit(fn -> Application.put_env(:symptoms, :api_token, previous) end)

    assert authed() |> get("/api/v1/symptoms/log") |> json_response(503)
  end

  test "shows the latest revision of a symptom", %{ids: [a | _]} do
    assert %{"symptom_id" => ^a, "revision" => 2} = authed() |> get("/api/v1/symptoms/#{a}") |> json_response(200)
    assert authed() |> get("/api/v1/symptoms/#{Log.uuid7(@at)}") |> json_response(404)
    assert authed() |> get("/api/v1/symptoms/not-a-uuid") |> json_response(404)
  end

  test "the board lists open board-tier symptoms by expected cost", %{ids: [a, _b, c]} do
    assert %{"symptoms" => symptoms} = authed() |> get("/api/v1/symptoms/board") |> json_response(200)
    assert Enum.map(symptoms, & &1["symptom_id"]) == [c, a]
  end

  test "metrics report coverage and pipeline lag without auth" do
    body = build_conn() |> get("/metrics") |> response(200)
    assert body =~ "symptoms_up 1\n"
    assert body =~ "symptoms_coverage_ratio 1.0\n"
    assert body =~ ~s(symptoms_open_symptoms{tier="board"} 2\n)
  end

  test "metrics show when no source is configured and no entity is expected" do
    # Test config has `sources: []` and no entity was seen: the coverage
    # ratio reads 1.0, so these two are what reveal it.
    body = build_conn() |> get("/metrics") |> response(200)
    assert body =~ "symptoms_sources_configured 0\n"
    assert body =~ "symptoms_entities_expected 0\n"

    previous = Application.get_env(:symptoms, :sources)
    on_exit(fn -> Application.put_env(:symptoms, :sources, previous) end)
    Application.put_env(:symptoms, :sources, [Symptoms.FakeSource])
    assert build_conn() |> get("/metrics") |> response(200) =~ "symptoms_sources_configured 1\n"
  end
end
