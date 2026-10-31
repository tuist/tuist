defmodule TuistWeb.RemoteExecutionControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.ProjectsFixtures

  alias Tuist.Cache
  alias Tuist.FeatureFlags
  alias Tuist.OAuth.Introspection
  alias Tuist.RemoteExecution

  setup %{conn: conn} do
    project = project_fixture()

    {:ok, _} =
      RemoteExecution.configure(project.account, %{
        max_concurrency: 2,
        node_names: ["reserved"],
        image_tag: "sha-" <> String.duplicate("a", 40),
        cas_endpoint: "grpcs://cache.example",
        executor_endpoint: "grpcs://execution.example"
      })

    %{
      conn: put_req_header(conn, "authorization", "Bearer test-token"),
      project: project,
      prefix: "/api/remote-execution/#{project.account.name}/#{project.name}"
    }
  end

  defp grant(project, write \\ true) do
    handle = "#{project.account.name}/#{project.name}"
    %{active: true, cache_grants: %{"project" => %{"read" => [handle], "write" => if(write, do: [handle], else: [])}}}
  end

  test "the existing signed project cache token authenticates execution", %{conn: conn, project: project} do
    stub(FeatureFlags, :bazel_remote_execution_enabled?, fn _ -> true end)
    {:ok, token, _claims} = Cache.issue_cache_token(project, scope: "#{project.account.name}/#{project.name}")
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    assert %{"cas_endpoint" => "grpcs://cache.example"} =
             conn
             |> get("/api/remote-execution/#{project.account.name}/#{project.name}/capabilities")
             |> json_response(:ok)
  end

  test "disabled accounts and read-only credentials cannot execute", %{conn: conn, project: project, prefix: prefix} do
    stub(Introspection, :token_response, fn _, _ -> grant(project) end)
    stub(FeatureFlags, :bazel_remote_execution_enabled?, fn _ -> false end)
    reject(&RemoteExecution.submit/2)
    params = %{"hash" => String.duplicate("a", 64), "size" => 10}

    assert conn |> get(prefix <> "/capabilities") |> json_response(:forbidden)
    assert conn |> post(prefix <> "/operations", params) |> json_response(:forbidden)

    stub(FeatureFlags, :bazel_remote_execution_enabled?, fn _ -> true end)
    stub(Introspection, :token_response, fn _, _ -> grant(project, false) end)
    assert conn |> post(prefix <> "/operations", params) |> json_response(:forbidden)
  end

  test "submission returns the operation the scheduler reports", %{conn: conn, project: project, prefix: prefix} do
    stub(Introspection, :token_response, fn _, _ -> grant(project) end)
    stub(FeatureFlags, :bazel_remote_execution_enabled?, fn _ -> true end)
    project_id = project.id

    expect(RemoteExecution, :submit, fn %{id: ^project_id}, %{"hash" => _, "size" => 10} ->
      {:ok, %{id: "op", state: "completed", done: true, response: "result", cacheable: true}}
    end)

    assert %{"id" => "op", "done" => true, "response" => "result", "cacheable" => true} =
             conn
             |> post(prefix <> "/operations", %{"hash" => String.duplicate("a", 64), "size" => 10})
             |> json_response(:accepted)

    for {error, status} <- [
          invalid_request: :bad_request,
          queue_full: :too_many_requests,
          unavailable: :service_unavailable
        ] do
      expect(RemoteExecution, :submit, fn _, _ -> {:error, error} end)
      assert conn |> post(prefix <> "/operations", %{}) |> json_response(status)
    end
  end

  test "operations stay readable after admission is disabled", %{conn: conn, project: project, prefix: prefix} do
    stub(Introspection, :token_response, fn _, _ -> grant(project) end)
    stub(FeatureFlags, :bazel_remote_execution_enabled?, fn _ -> false end)
    id = Ecto.UUID.generate()

    expect(RemoteExecution, :await, fn %{id: _}, ^id, "executing" -> {:ok, %{id: id, state: "completed", done: true}} end)

    assert %{"id" => ^id, "done" => true} =
             conn |> get(prefix <> "/operations/#{id}?after=executing") |> json_response(:ok)

    expect(RemoteExecution, :await, fn _, _, _ -> {:error, :not_found} end)
    assert conn |> get(prefix <> "/operations/#{id}") |> json_response(:not_found)

    stub(Introspection, :token_response, fn _, _ -> %{active: false} end)
    assert conn |> get(prefix <> "/operations/#{id}") |> json_response(:forbidden)
  end
end
