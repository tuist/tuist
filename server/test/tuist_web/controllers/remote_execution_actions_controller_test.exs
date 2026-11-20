defmodule TuistWeb.RemoteExecutionActionsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.ProjectsFixtures

  alias Tuist.FeatureFlags
  alias Tuist.OAuth.Introspection
  alias Tuist.RemoteExecution.Actions
  alias Tuist.Storage

  setup %{conn: conn} do
    project = project_fixture(build_system: :bazel)

    %{
      conn: put_req_header(conn, "authorization", "Bearer test-token"),
      project: project,
      path: "/api/remote-execution/#{project.account.name}/#{project.name}/actions"
    }
  end

  defp grant(project, write) do
    handle = "#{project.account.name}/#{project.name}"
    %{active: true, cache_grants: %{"project" => %{"read" => [handle], "write" => if(write, do: [handle], else: [])}}}
  end

  defp record do
    %{
      "operation_id" => Ecto.UUID.generate(),
      "action_hash" => String.duplicate("c", 64),
      "invocation_id" => "inv-1",
      "arguments" => ["true"]
    }
  end

  test "stores records sent with the project's execution credential, even after execution was disabled",
       %{conn: conn, project: project, path: path} do
    stub(Introspection, :token_response, fn _, _ -> grant(project, true) end)
    stub(FeatureFlags, :bazel_remote_execution_enabled?, fn _ -> false end)
    rec = record()

    assert %{"accepted" => 1} = conn |> post(path, %{"actions" => [rec]}) |> json_response(:accepted)
    assert {:ok, %{arguments: ["true"]}} = Actions.get(project.id, "inv-1", rec["operation_id"])
  end

  test "answers with uploads for the ends of long streams", %{conn: conn, project: project, path: path} do
    stub(Introspection, :token_response, fn _, _ -> grant(project, true) end)
    stub(Storage, :generate_upload_url, fn key, _actor, _opts -> "https://storage.example/" <> key end)
    hash = String.duplicate("d", 64)

    rec =
      Map.merge(record(), %{"stderr" => "e", "stderr_size" => 100_000, "stderr_truncated" => true, "stderr_hash" => hash})

    assert %{"accepted" => 2, "log_uploads" => [upload]} =
             conn |> post(path, %{"actions" => [rec, record()]}) |> json_response(:accepted)

    assert upload == %{
             "hash" => hash,
             "size" => 100_000,
             "offset" => 0,
             "length" => 100_000,
             "url" =>
               "https://storage.example/#{project.account.name}/#{project.name}/runs/inv-1/remote-actions/#{rec["operation_id"]}/stderr.log"
           }
  end

  test "refuses credentials that cannot write the project's cache", %{conn: conn, project: project, path: path} do
    stub(Introspection, :token_response, fn _, _ -> grant(project, false) end)
    rec = record()

    assert conn |> post(path, %{"actions" => [rec]}) |> json_response(:forbidden)
    assert {:error, :not_found} = Actions.get(project.id, "inv-1", rec["operation_id"])
  end

  test "refuses a credential for another project", %{conn: conn, project: project} do
    other = project_fixture()
    stub(Introspection, :token_response, fn _, _ -> grant(project, true) end)

    assert conn
           |> post("/api/remote-execution/#{other.account.name}/#{other.name}/actions", %{"actions" => [record()]})
           |> json_response(:forbidden)
  end

  test "rejects malformed and oversized batches", %{conn: conn, project: project, path: path} do
    stub(Introspection, :token_response, fn _, _ -> grant(project, true) end)

    assert conn |> post(path, %{"actions" => "nope"}) |> json_response(:bad_request)
    assert conn |> post(path, %{}) |> json_response(:bad_request)

    assert conn
           |> post(path, %{"actions" => List.duplicate(record(), Actions.max_records() + 1)})
           |> json_response(:bad_request)
  end
end
