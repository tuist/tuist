defmodule TuistWeb.Internal.AtlasFeatureFlagsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias FunWithFlags.Flag
  alias FunWithFlags.Store.Persistent.Ecto, as: Persistence
  alias Tuist.AtlasWorkloadIdentity
  alias Tuist.Ops.FeatureFlagChange
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.RateLimit

  setup :set_mimic_from_context

  setup do
    stub(RateLimit.Atlas, :hit, fn _conn -> {:allow, 1} end)
    stub(AtlasWorkloadIdentity, :verify, fn "valid-token" -> {:ok, %{namespace: "atlas-production", name: "atlas"}} end)
    :ok
  end

  test "internal routes reject unauthenticated callers, including writes", %{conn: conn} do
    assert conn |> get("/api/internal/atlas/flags") |> json_response(401)
    assert conn |> put("/api/internal/atlas/flags/runners", %{}) |> json_response(401)
  end

  test "catalog includes inactive flags and rejects unknown names", %{conn: conn} do
    assert %{"flags" => flags} = conn |> authed() |> get("/api/internal/atlas/flags") |> json_response(200)
    assert Enum.any?(flags, &(&1["name"] == "runners" and &1["actor_type"] == "account"))
    assert Enum.any?(flags, &(&1["name"] == "build_entities_kill_switch" and &1["actor_type"] == "global"))
    assert conn |> authed() |> get("/api/internal/atlas/flags/not-a-flag") |> json_response(404)
  end

  test "global changes preserve explicit account exclusions and clear restores inheritance", %{conn: conn} do
    excluded = AccountsFixtures.user_fixture().account
    included = AccountsFixtures.user_fixture().account

    change(conn, "runners", %{"operation" => "disable", "scope" => "account", "account_id" => excluded.id})
    change(conn, "runners", %{"operation" => "enable", "scope" => "global"})
    assert {:ok, flag} = Persistence.get(:runners)
    assert Flag.enabled?(flag, for: included)
    refute Flag.enabled?(flag, for: excluded)

    change(conn, "runners", %{"operation" => "clear", "scope" => "account", "account_id" => excluded.id})
    assert {:ok, flag} = Persistence.get(:runners)
    assert Flag.enabled?(flag, for: excluded)

    change(conn, "runners", %{"operation" => "enable", "scope" => "account", "account_id" => included.id})
    change(conn, "runners", %{"operation" => "disable", "scope" => "global"})
    assert {:ok, flag} = Persistence.get(:runners)
    assert Flag.enabled?(flag, for: included)
    refute Flag.enabled?(flag, for: excluded)
  end

  test "project gates cannot enroll accounts, and percentage cohorts only grow", %{conn: conn} do
    project = ProjectsFixtures.project_fixture()
    change(conn, "build_entities", %{"operation" => "enable", "scope" => "project", "project_id" => project.id})
    assert {:ok, flag} = Persistence.get(:build_entities)
    assert Flag.enabled?(flag, for: project)
    refute Flag.enabled?(flag, for: %{project | id: project.id + 1})

    # Asymmetric cohorts distinguish stable actor hashing from a random/time gate.
    actors = Enum.map(1..200, &%Tuist.Accounts.Account{id: &1})
    change(conn, "runners", %{"operation" => "enable", "scope" => "percentage", "percentage" => 12.5})
    assert {:ok, small} = Persistence.get(:runners)
    cohort = Enum.filter(actors, &Flag.enabled?(small, for: &1))
    assert cohort != [] and length(cohort) < 100

    change(conn, "runners", %{"operation" => "enable", "scope" => "percentage", "percentage" => 75})
    assert {:ok, large} = Persistence.get(:runners)
    assert Enum.all?(cohort, &Flag.enabled?(large, for: &1))
    assert Enum.count(actors, &Flag.enabled?(large, for: &1)) > length(cohort)

    change(conn, "runners", %{"operation" => "clear", "scope" => "percentage"})
    assert {:ok, cleared} = Persistence.get(:runners)
    refute Enum.any?(actors, &Flag.enabled?(cleared, for: &1))
  end

  test "retries are idempotent and stale revisions or reused change IDs cannot overwrite a later change", %{conn: conn} do
    request = request(conn, "runners", %{"operation" => "enable", "scope" => "global"})
    first = conn |> authed() |> put("/api/internal/atlas/flags/runners", request) |> json_response(200)
    second = change(conn, "runners", %{"operation" => "clear", "scope" => "all"})
    refute second["revision"] == request["expected_revision"]
    assert second["gates"] == []

    assert conn |> authed() |> put("/api/internal/atlas/flags/runners", request) |> json_response(200) == first
    stale = Map.put(request, "change_id", Ecto.UUID.generate())

    assert %{"error" => "stale_revision"} =
             conn |> authed() |> put("/api/internal/atlas/flags/runners", stale) |> json_response(409)

    reused = Map.put(request, "reason", "Different request")

    assert %{"error" => "change_id_conflict"} =
             conn |> authed() |> put("/api/internal/atlas/flags/runners", reused) |> json_response(409)

    assert Repo.aggregate(FeatureFlagChange, :count) == 2
    audit = Repo.get_by!(FeatureFlagChange, change_id: request["change_id"])
    assert audit.principal == %{"namespace" => "atlas-production", "name" => "atlas"}
    assert audit.request["actor"] == request["actor"]
    assert audit.request["reason"] == request["reason"]
    assert audit.before["revision"] == request["expected_revision"]
    assert audit.after == first
    assert {:ok, flag} = Persistence.get(:runners)
    assert flag.gates == []
  end

  test "invalid scope, target, percentages and forged fields never mutate flags", %{conn: conn} do
    for attrs <- [
          %{"scope" => "project", "project_id" => 1},
          %{"scope" => "account", "account_id" => -1},
          %{"scope" => "global", "account_id" => 1},
          %{"scope" => "percentage", "percentage" => 0},
          %{"scope" => "percentage", "percentage" => 100},
          %{"scope" => "percentage", "percentage" => "10"},
          %{"scope" => "all"},
          %{"scope" => "global", "reason" => " "},
          %{"scope" => "global", "actor" => %{"id" => "forged", "email" => "test@example.com"}},
          %{"scope" => "global", "unexpected" => true}
        ] do
      params = request(conn, "runners", Map.put_new(attrs, "operation", "enable"))
      assert conn |> authed() |> put("/api/internal/atlas/flags/runners", params) |> json_response(422)
    end

    assert Repo.aggregate(FeatureFlagChange, :count) == 0
  end

  defp authed(conn), do: put_req_header(conn, "authorization", "Bearer valid-token")

  defp change(conn, name, attrs) do
    params = request(conn, name, attrs)
    conn |> authed() |> put("/api/internal/atlas/flags/#{name}", params) |> json_response(200)
  end

  defp request(conn, name, attrs) do
    %{"revision" => revision} = conn |> authed() |> get("/api/internal/atlas/flags/#{name}") |> json_response(200)

    Map.merge(
      %{
        "expected_revision" => revision,
        "reason" => "Measured rollout",
        "change_id" => Ecto.UUID.generate(),
        "actor" => %{"id" => "273ee746-33fb-4db0-bc1d-7c3b6a602e6d", "email" => "operator@example.com"},
        "interface" => "mcp"
      },
      attrs
    )
  end
end
