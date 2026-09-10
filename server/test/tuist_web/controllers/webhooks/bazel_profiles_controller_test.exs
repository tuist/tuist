defmodule TuistWeb.Webhooks.BazelProfilesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Bazel.Invocation
  alias Tuist.Bazel.Profile
  alias Tuist.Builds.RecordedSteps
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    stub(Tuist.Environment, :cache_api_key, fn -> "profile-test-key" end)
    %{project: project, account: user.account}
  end

  test "signed profiles retain all intervals, attach action outcomes and fetch sanitized logs separately", %{
    conn: conn,
    project: project,
    account: account
  } do
    identity = %{account_handle: account.name, project_handle: project.name, invocation_id: "profile-test"}

    events =
      Enum.map(1..70, fn i ->
        %{
          ph: "X",
          name: "Compile #{i}",
          ts: i * 1000,
          dur: 500,
          args: %{out: "out/#{i}.o", target: "//:app", mnemonic: "CppCompile"}
        }
      end)

    compressed = :zlib.gzip(JSON.encode!(%{otherData: %{build_id: "profile-test"}, traceEvents: events}))

    payload =
      Map.merge(identity, %{
        digest: Base.encode16(:crypto.hash(:sha256, compressed), case: :lower),
        content_base64: Base.encode64(compressed)
      })

    assert conn |> signed_post("/webhooks/bazel-profiles", payload) |> response(202)

    action =
      Map.merge(identity, %{
        primary_output: "out/1.o",
        started_at_ms: 123,
        success: false,
        log: "compiler error\nAuthorization: Bearer sensitive-token",
        log_truncated: false
      })

    assert conn |> signed_post("/webhooks/bazel-actions", action) |> response(202)

    build = %Invocation{project_id: project.id, invocation_id: "profile-test"}

    assert {:ok, %{steps: steps, pagination_metadata: %{total_count: 70}, coverage: "trace_profile"}} =
             RecordedSteps.list(build, %{page_size: 100})

    refute Enum.any?(steps, &Map.has_key?(&1, :log))
    refute Enum.any?(steps, &Map.has_key?(&1, :primary_output))
    failed = Enum.find(steps, &(&1.status == "failure"))
    assert {:ok, %{log: log}} = RecordedSteps.get(build, failed.id)
    assert log =~ "compiler error"
    refute log =~ "sensitive-token"
    assert Profile.load(%{build | project_id: project.id + 1}) == nil
  end

  test "rejects unsigned profiles and digest mismatches", %{conn: conn, project: project, account: account} do
    assert conn |> post("/webhooks/bazel-profiles", %{}) |> response(401)

    payload = %{
      account_handle: account.name,
      project_handle: project.name,
      invocation_id: "build",
      digest: String.duplicate("a", 64),
      content_base64: Base.encode64(:zlib.gzip("{}"))
    }

    assert conn |> signed_post("/webhooks/bazel-profiles", payload) |> response(400)
  end

  defp signed_post(conn, path, payload) do
    body = JSON.encode!(payload)
    signature = :hmac |> :crypto.mac(:sha256, "profile-test-key", body) |> Base.encode16(case: :lower)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cache-signature", signature)
    |> put_req_header("x-cache-endpoint", "localhost:9867")
    |> post(path, body)
  end
end
