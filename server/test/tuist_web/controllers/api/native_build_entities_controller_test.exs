defmodule TuistWeb.API.NativeBuildEntitiesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.QueryLimitError
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BuildEntitiesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.BuildEntityResources
  alias TuistWeb.API.Schemas.BuildEntity
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{conn: Authentication.put_current_user(conn, user), user: user}
  end

  test "duration sample counts are optional additive fields in all analytics metric schemas" do
    properties = BuildEntity.analytics().properties

    for schema <- [properties.total, properties.previous, properties.points.items] do
      assert schema.properties.duration_samples.minimum == 0
      refute :duration_samples in schema.required
    end
  end

  for resource <- BuildEntityResources.all() do
    test "#{resource.key} expose native identities, analytics and history without a run ID", %{conn: conn, user: user} do
      resource = unquote(Macro.escape(resource))
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: resource.system)
      %{entity: entity, observation: observation} = BuildEntitiesFixtures.entity_fixture(project, resource.key)
      path = "/api/projects/#{user.account.name}/#{project.name}#{resource.api_path}"

      inventory = conn |> get(path) |> json_response(200)
      assert [%{"id" => id}] = inventory[to_string(resource.plural)]
      assert id == entity.id
      refute Map.has_key?(inventory, "build_entities")

      detail = conn |> get(path <> "/#{entity.id}") |> json_response(200)
      assert detail[to_string(resource.singular)]["identity"] == entity.identity
      assert detail["analytics"]["total"]["observations"] == 1
      assert detail["analytics"]["total"]["duration_samples"] == 1
      assert detail["analytics"]["previous"]["duration_samples"] == 0
      assert detail["analytics"]["total"]["avg_duration_ms"] == 120.0
      assert is_nil(detail["analytics"]["total"]["hit_rate"])

      history = conn |> get(path <> "/#{entity.id}/#{resource.history_path}") |> json_response(200)
      assert [execution] = history[to_string(resource.history_key)]
      assert execution["parent_id"] == observation.parent_id
      assert execution["execution_id"] == observation.execution_id
      assert execution["status"] == "success"
      assert execution["cache_status"] == "none"

      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: resource.system)
      FunWithFlags.enable(:build_entities, for_actor: other_project)
      other_path = "/api/projects/#{user.account.name}/#{other_project.name}#{resource.api_path}/#{entity.id}"
      assert %{"message" => "Not found in this project."} = conn |> get(other_path) |> json_response(404)
    end
  end

  test "exact-key Xcode and Bazel cache actions are not exposed", %{conn: conn, user: user} do
    assert Enum.map(BuildEntityResources.all(), & &1.key) ==
             ~w(gradle_tasks xcode_modules once_actions mix_files mix_modules)a

    for {system, path} <- [xcode: "/xcode/cache-actions", bazel: "/bazel/cache-actions"] do
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: system)
      assert response(get(conn, "/api/projects/#{user.account.name}/#{project.name}#{path}"), 404)
    end
  end

  test "rejects unsupported toolchains, invalid ranges and invalid history cursors", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    root = "/api/projects/#{user.account.name}/#{project.name}"
    path = root <> "/gradle/tasks"

    assert %{"message" => "Not found in this project."} = conn |> get(root <> "/mix/files") |> json_response(404)
    assert %{"message" => _} = conn |> get(path <> "?start_at=invalid") |> json_response(400)
    assert %{"message" => _} = conn |> get(path <> "/#{entity.id}/executions?after=invalid") |> json_response(400)
  end

  test "history exposes stable forward/backward cursors and nullable page numbers", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    path = "/api/projects/#{user.account.name}/#{project.name}/gradle/tasks/#{entity.id}/executions?page_size=2"

    first = conn |> get(path) |> json_response(200)
    assert length(first["executions"]) == 2
    assert first["pagination_metadata"]["total_count"] == 3
    assert after_cursor = first["pagination_metadata"]["after"]

    second = conn |> get(path <> "&after=#{after_cursor}") |> json_response(200)
    assert length(second["executions"]) == 1
    assert is_nil(second["pagination_metadata"]["current_page"])
    refute second["pagination_metadata"]["has_next_page"]
    assert before_cursor = second["pagination_metadata"]["before"]

    previous = conn |> get(path <> "&before=#{before_cursor}") |> json_response(200)
    assert previous["executions"] == first["executions"]
  end

  test "bounded analytics failures return a retryable service error", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    FunWithFlags.enable(:build_entities, for_actor: project)
    stub(BuildEntities, :list, fn _project_id, _system, _kind, _opts -> raise QueryLimitError end)

    assert %{"message" => "The query exceeded analytics limits. Please try again later."} =
             conn
             |> get("/api/projects/#{user.account.name}/#{project.name}/gradle/tasks")
             |> json_response(503)
  end

  test "disabled projects and the kill switch hide new resources before querying", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    root = "/api/projects/#{user.account.name}/#{project.name}/gradle/tasks"
    id = UUIDv7.generate()
    reject(BuildEntities, :list, 4)
    reject(BuildEntities, :get, 4)

    for path <- [root, root <> "/#{id}", root <> "/#{id}/executions"] do
      assert %{"message" => "Not found in this project."} = conn |> get(path) |> json_response(404)
    end

    FunWithFlags.enable(:build_entities, for_actor: project)
    stub(FunWithFlags, :enabled?, fn :build_entities_kill_switch -> true end)
    assert %{"message" => "Not found in this project."} = conn |> get(root) |> json_response(404)
  end

  test "checks project permissions before exposing a persistent identity", %{conn: conn, user: user} do
    owner = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: owner.account.id, build_system: :gradle)
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    assert user.id != owner.id

    conn
    |> get("/api/projects/#{owner.account.name}/#{project.name}/gradle/tasks/#{entity.id}")
    |> json_response(403)
  end
end
