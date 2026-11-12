defmodule TuistWeb.Internal.AtlasAccountsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.AtlasWorkloadIdentity
  alias Tuist.Ops.RunnerConcurrencyLimitChange
  alias Tuist.Repo
  alias Tuist.Runners.Concurrency
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.RateLimit

  setup do
    stub(RateLimit.Atlas, :hit, fn _conn -> {:allow, 1} end)
    stub(AtlasWorkloadIdentity, :verify, fn "valid-token" -> {:ok, %{namespace: "atlas-production", name: "atlas"}} end)
    :ok
  end

  test "routes reject unauthenticated callers, including writes", %{conn: conn} do
    assert conn |> get("/api/internal/atlas/accounts/lookup", %{"handle" => "tuist"}) |> json_response(401)
    assert conn |> get("/api/internal/atlas/accounts/1/runner-concurrency-limits") |> json_response(401)
    assert conn |> put("/api/internal/atlas/accounts/1/runner-concurrency-limits", %{}) |> json_response(401)
  end

  test "lookup resolves an organization handle to its account ID, not the organization ID", %{conn: conn} do
    organization = AccountsFixtures.organization_fixture(name: "SteyCorp", preload: [:account])
    user = AccountsFixtures.user_fixture(preload: [:account])

    assert conn |> authed() |> get("/api/internal/atlas/accounts/lookup", %{"handle" => "steycorp"}) |> json_response(200) ==
             %{
               "account_id" => organization.account.id,
               "handle" => "SteyCorp",
               "type" => "organization",
               "organization_id" => organization.id,
               "user_id" => nil
             }

    assert %{"account_id" => account_id, "type" => "user", "user_id" => user_id} =
             conn
             |> authed()
             |> get("/api/internal/atlas/accounts/lookup", %{"handle" => user.account.name})
             |> json_response(200)

    assert account_id == user.account.id
    assert user_id == user.id

    assert %{"error" => "resource_not_found"} =
             conn
             |> authed()
             |> get("/api/internal/atlas/accounts/lookup", %{"handle" => "missing"})
             |> json_response(404)

    assert %{"error" => "invalid_request"} =
             conn |> authed() |> get("/api/internal/atlas/accounts/lookup") |> json_response(422)
  end

  test "reads limits with usage and defaults, and rejects unknown or malformed accounts", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    assert %{"account_id" => account_id, "account_handle" => handle, "revision" => revision, "limits" => limits} =
             conn |> authed() |> get(path(account.id)) |> json_response(200)

    assert account_id == account.id
    assert handle == account.name
    assert byte_size(revision) == 64

    assert limits == [
             %{
               "platform" => "linux",
               "vcpus" => 32,
               "memory_gb" => 64,
               "used_vcpus" => 0,
               "used_memory_gb" => 0,
               "default_vcpus" => 32,
               "default_memory_gb" => 64
             },
             %{
               "platform" => "macos",
               "vcpus" => 16,
               "memory_gb" => 48,
               "used_vcpus" => 0,
               "used_memory_gb" => 0,
               "default_vcpus" => 16,
               "default_memory_gb" => 48
             }
           ]

    assert %{"error" => "resource_not_found"} =
             conn |> authed() |> get(path(9_223_372_036_854_775_807)) |> json_response(404)

    for id <- ["0", "-1", "1.5", "9223372036854775808", "abc"] do
      assert %{"error" => "invalid_target"} = conn |> authed() |> get(path(id)) |> json_response(422)
    end
  end

  test "updates only the requested platform and audits the change atomically", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    other = AccountsFixtures.organization_fixture(preload: [:account]).account
    request = request(conn, account.id, %{"platform" => "macos", "vcpus" => 48, "memory_gb" => 144})

    result = conn |> authed() |> put(path(account.id), request) |> json_response(200)

    assert Enum.find(result["limits"], &(&1["platform"] == "macos"))["vcpus"] == 48
    assert Concurrency.limits_for(account, :macos) == %{vcpus: 48, memory_gb: 144}
    assert Concurrency.limits_for(account, :linux) == %{vcpus: 32, memory_gb: 64}
    assert Concurrency.limits_for(other, :macos) == %{vcpus: 16, memory_gb: 48}
    refute result["revision"] == request["expected_revision"]

    audit = Repo.get_by!(RunnerConcurrencyLimitChange, change_id: request["change_id"])
    assert audit.account_id == account.id
    assert audit.principal == %{"namespace" => "atlas-production", "name" => "atlas"}
    assert audit.request == request
    assert audit.before["revision"] == request["expected_revision"]
    assert Enum.find(audit.before["limits"], &(&1["platform"] == "macos"))["vcpus"] == 16
    assert audit.after == result
  end

  test "retries are idempotent and stale revisions or reused change IDs cannot overwrite a later change", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account
    request = request(conn, account.id, %{"platform" => "linux", "vcpus" => 64, "memory_gb" => 128})
    first = conn |> authed() |> put(path(account.id), request) |> json_response(200)

    later = request(conn, account.id, %{"platform" => "linux", "vcpus" => 40, "memory_gb" => 80})
    conn |> authed() |> put(path(account.id), later) |> json_response(200)

    # The original request replays its recorded result without reapplying it.
    assert conn |> authed() |> put(path(account.id), request) |> json_response(200) == first
    assert Concurrency.limits_for(account, :linux) == %{vcpus: 40, memory_gb: 80}

    stale = Map.put(request, "change_id", Ecto.UUID.generate())

    assert %{"error" => "stale_revision"} =
             conn |> authed() |> put(path(account.id), stale) |> json_response(409)

    reused = Map.put(request, "reason", "Different request")

    assert %{"error" => "change_id_conflict"} =
             conn |> authed() |> put(path(account.id), reused) |> json_response(409)

    other = AccountsFixtures.organization_fixture(preload: [:account]).account
    elsewhere = request(conn, other.id, Map.take(request, ~w(platform vcpus memory_gb change_id)))

    assert %{"error" => "change_id_conflict"} =
             conn |> authed() |> put(path(other.id), elsewhere) |> json_response(409)

    assert Concurrency.limits_for(account, :linux) == %{vcpus: 40, memory_gb: 80}
    assert Concurrency.limits_for(other, :linux) == %{vcpus: 32, memory_gb: 64}
    assert Repo.aggregate(RunnerConcurrencyLimitChange, :count) == 2
  end

  test "ops dashboard edits invalidate the revision Atlas read, even when they restore the same values", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    # Back-date the rows so the dashboard writes land in a later second.
    Repo.update_all(Ecto.assoc(account, :runner_concurrency_limits), set: [updated_at: ~U[2026-01-01 00:00:00Z]])
    request = request(conn, account.id, %{"platform" => "macos", "vcpus" => 32, "memory_gb" => 96})

    for {vcpus, memory_gb} <- [{24, 72}, {16, 48}] do
      {:ok, _} =
        Concurrency.update_limits(account, %{
          runner_linux_vcpus_limit: 32,
          runner_linux_memory_gb_limit: 64,
          runner_macos_vcpus_limit: vcpus,
          runner_macos_memory_gb_limit: memory_gb
        })
    end

    assert %{"error" => "stale_revision"} =
             conn |> authed() |> put(path(account.id), request) |> json_response(409)

    assert Concurrency.limits_for(account, :macos) == %{vcpus: 16, memory_gb: 48}
  end

  test "invalid limits and forged or unknown fields never change limits", %{conn: conn} do
    account = AccountsFixtures.organization_fixture(preload: [:account]).account

    for attrs <- [
          %{"platform" => "windows"},
          %{"vcpus" => 0},
          %{"memory_gb" => -1},
          %{"vcpus" => "32"},
          %{"vcpus" => 1.5},
          %{"vcpus" => 2_147_483_648},
          %{"reason" => " "},
          %{"change_id" => "not-a-uuid"},
          %{"expected_revision" => "short"},
          %{"actor" => %{"id" => "forged", "email" => "test@example.com"}},
          %{"interface" => "slack"},
          %{"account_id" => account.id}
        ] do
      params = request(conn, account.id, Map.merge(%{"platform" => "macos", "vcpus" => 32, "memory_gb" => 96}, attrs))

      assert %{"error" => "invalid_request"} =
               conn |> authed() |> put(path(account.id), params) |> json_response(422)
    end

    params = request(conn, account.id, %{"platform" => "macos", "vcpus" => 32})
    assert conn |> authed() |> put(path(account.id), params) |> json_response(422)

    assert Concurrency.limits_for(account, :macos) == %{vcpus: 16, memory_gb: 48}
    assert Repo.aggregate(RunnerConcurrencyLimitChange, :count) == 0
  end

  defp authed(conn), do: put_req_header(conn, "authorization", "Bearer valid-token")

  defp path(account_id), do: "/api/internal/atlas/accounts/#{account_id}/runner-concurrency-limits"

  defp request(conn, account_id, attrs) do
    %{"revision" => revision} = conn |> authed() |> get(path(account_id)) |> json_response(200)

    Map.merge(
      %{
        "expected_revision" => revision,
        "reason" => "Customer onboarding to runners",
        "change_id" => Ecto.UUID.generate(),
        "actor" => %{"id" => "273ee746-33fb-4db0-bc1d-7c3b6a602e6d", "email" => "operator@example.com"},
        "interface" => "mcp"
      },
      attrs
    )
  end
end
