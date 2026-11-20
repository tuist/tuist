defmodule TuistWeb.API.BazelRemoteActionsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.GetBazelRemoteAction
  alias Tuist.MCP.Components.Tools.GetBazelRemoteActionLog
  alias Tuist.MCP.Components.Tools.ListBazelRemoteActions
  alias Tuist.RemoteExecution.Actions
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  @queued 1_793_157_000_000_000

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    invocation_id = Ecto.UUID.generate()
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      %{
        project_id: project.id,
        invocation_id: invocation_id,
        account_handle: user.account.name,
        project_handle: project.name,
        command: "build",
        status: "failure",
        exit_code: 1,
        started_at: now,
        finished_at: now,
        duration_ms: 500,
        target_patterns: [],
        cache_endpoint: ""
      }
    ])

    record = fn overrides ->
      Map.merge(
        %{
          "operation_id" => Ecto.UUID.generate(),
          "action_hash" => String.duplicate("a", 64),
          "action_size" => 140,
          "invocation_id" => invocation_id,
          "mnemonic" => "CppCompile",
          "target" => "//pkg:lib",
          "arguments" => ["gcc", "-c", "lib.c"],
          "environment" => [%{"name" => "NPM_TOKEN", "value" => "npm_x"}],
          "platform" => [%{"name" => "OSFamily", "value" => "Linux"}],
          "output_paths" => ["bazel-out/lib.o"],
          "timestamps" => %{"queued" => @queued, "worker_completed" => @queued + 2_000_000},
          "stderr" => "lib.c:1: error"
        },
        overrides
      )
    end

    ok = record.(%{"exit_code" => 0})
    failed = record.(%{"exit_code" => 1, "mnemonic" => "CppLink"})
    {:ok, 2} = Actions.ingest(project, [ok, failed])

    %{
      conn: Authentication.put_current_user(conn, user),
      user: user,
      path: "/api/projects/#{user.account.name}/#{project.name}/bazel/invocations/#{invocation_id}/remote-actions",
      args: %{"account_handle" => user.account.name, "project_handle" => project.name, "invocation_id" => invocation_id},
      failed: failed,
      project: project
    }
  end

  test "lists and inspects an invocation's remote actions", %{conn: conn, path: path, failed: failed} do
    list = conn |> get(path) |> json_response(200)
    assert_schema(list, "BazelRemoteActionsList", Spec.spec())
    assert %{"actions" => [_, _], "pagination_metadata" => %{"total_count" => 2}} = list

    assert %{"actions" => [%{"id" => id, "exit_code" => 1, "mnemonic" => "CppLink", "duration_ms" => 2000.0}]} =
             conn |> get(path, %{failed: true}) |> json_response(200)

    assert id == failed["operation_id"]

    detail = conn |> get(path <> "/" <> id) |> json_response(200)
    assert_schema(detail, "BazelRemoteActionDetail", Spec.spec())
    assert detail["arguments"] == ["gcc", "-c", "lib.c"]
    assert detail["environment"] == [%{"name" => "NPM_TOKEN", "value" => "****"}]
    assert detail["stderr"] == "lib.c:1: error"
    assert detail["timestamps"]["queued"] =~ ~r/Z\z/

    assert conn |> get(path <> "/" <> Ecto.UUID.generate()) |> json_response(404)
    assert conn |> get(path <> "/not-a-uuid") |> json_response(404)
  end

  test "an unknown invocation is not found and other accounts are forbidden", %{conn: conn, path: path} do
    unknown = String.replace(path, ~r{invocations/[^/]+}, "invocations/missing")
    assert conn |> get(unknown) |> json_response(404)

    stranger = Authentication.put_current_user(build_conn(), AccountsFixtures.user_fixture())
    assert stranger |> get(path) |> json_response(403)
  end

  test "MCP tools list, filter and get remote actions", %{user: user, args: args, failed: failed} do
    conn = %Plug.Conn{assigns: %{current_user: user}}
    stranger = %Plug.Conn{assigns: %{current_user: AccountsFixtures.user_fixture()}}

    result = ListBazelRemoteActions.call(conn, Map.put(args, "mnemonic", "CppLink"))
    refute result["isError"]
    assert %{"actions" => [%{"id" => id}], "pagination_metadata" => %{"total_count" => 1}} = decode(result)
    assert id == failed["operation_id"]

    detail = GetBazelRemoteAction.call(conn, Map.put(args, "action_id", id))
    refute detail["isError"]
    assert %{"exit_code" => 1, "platform" => [%{"name" => "OSFamily", "value" => "Linux"}]} = decode(detail)

    assert GetBazelRemoteAction.call(conn, Map.put(args, "action_id", Ecto.UUID.generate()))["isError"]
    assert ListBazelRemoteActions.call(stranger, args)["isError"]
  end

  test "REST and MCP read a long stream's stored end", %{
    conn: conn,
    user: user,
    project: project,
    path: path,
    args: args,
    failed: failed
  } do
    id = Ecto.UUID.generate()
    stream = String.duplicate("0123456789", 10_000)
    tail = binary_part(stream, 60_000, 40_000)
    preview = binary_part(stream, 0, 16_384)

    {:ok, 1} =
      Actions.ingest(project, [
        Map.merge(failed, %{
          "operation_id" => id,
          "stderr" => preview,
          "stderr_size" => 100_000,
          "stderr_truncated" => true
        })
      ])

    stub(Storage, :get_object_as_string, fn key, _actor ->
      if String.ends_with?(key, "/remote-actions/#{id}/stderr.log"), do: tail
    end)

    # Without an offset, the end of the stream; the gap before the copy is not recorded.
    log = conn |> get(path <> "/" <> id <> "/logs/stderr") |> json_response(200)
    assert_schema(log, "BazelRemoteActionLog", Spec.spec())

    assert %{
             "offset" => 60_000,
             "size_bytes" => 100_000,
             "recorded" => [%{"offset" => 0, "length" => 16_384}, %{"offset" => 60_000, "length" => 40_000}]
           } = log

    assert log["text"] == tail

    # A window inside the gap is empty; one that reaches the copy starts where it does.
    assert %{"offset" => 20_000, "text" => ""} =
             conn |> get(path <> "/" <> id <> "/logs/stderr", %{offset: 20_000, limit: 1000}) |> json_response(200)

    assert %{"offset" => 60_000, "text" => "0123456789"} =
             conn |> get(path <> "/" <> id <> "/logs/stderr", %{offset: 59_990, limit: 20}) |> json_response(200)

    assert %{"text" => "0123456789"} =
             conn |> get(path <> "/" <> id <> "/logs/stderr", %{offset: 10, limit: 10}) |> json_response(200)

    mcp = %Plug.Conn{assigns: %{current_user: user}}

    result =
      GetBazelRemoteActionLog.call(mcp, Map.merge(args, %{"action_id" => id, "stream" => "stderr", "offset" => 99_990}))

    refute result["isError"]
    assert %{"offset" => 99_990, "text" => "0123456789"} = decode(result)

    stranger = %Plug.Conn{assigns: %{current_user: AccountsFixtures.user_fixture()}}
    assert GetBazelRemoteActionLog.call(stranger, Map.merge(args, %{"action_id" => id, "stream" => "stderr"}))["isError"]
  end

  defp decode(%{"content" => [%{"text" => text}]}), do: JSON.decode!(text)
end
