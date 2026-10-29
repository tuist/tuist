defmodule Tuist.MCP.Components.Tools.NativeBuildEntityToolsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Components.Tools
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BuildEntitiesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.BuildEntityResources

  @kinds [:gradle_tasks, :xcode_modules, :once_actions, :mix_files, :mix_modules, :bazel_actions]

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{user: user, conn: %{assigns: %{current_subject: user}}}
  end

  test "exposes three read-only tools whose kind enum lists exactly the supported kinds" do
    expected = Enum.map(@kinds, &Atom.to_string/1)

    for {tool, name} <- [
          {Tools.ListBuildEntities, "list_build_entities"},
          {Tools.GetBuildEntity, "get_build_entity"},
          {Tools.ListBuildEntityHistory, "list_build_entity_history"}
        ] do
      assert tool.name() == name
      assert tool.input_schema()["properties"]["kind"]["enum"] == expected
      assert "kind" in tool.input_schema()["required"]
      assert tool.output_schema()["properties"]["kind"]["enum"] == expected
    end

    assert "id" in Tools.GetBuildEntity.input_schema()["required"]
    assert "id" in Tools.ListBuildEntityHistory.input_schema()["required"]
    refute Map.has_key?(Tools.ListBuildEntities.input_schema()["properties"], "id")
  end

  for key <- @kinds do
    test "#{key} returns schema-valid list, detail and history results", %{conn: conn, user: user} do
      key = unquote(key)
      resource = BuildEntityResources.fetch!(key)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: resource.system)
      FunWithFlags.enable(:build_entities, for_actor: project)
      %{entity: entity, observation: observation} = BuildEntitiesFixtures.entity_fixture(project, key)

      arguments = %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "kind" => Atom.to_string(key)
      }

      inventory = Tools.ListBuildEntities.call(conn, arguments)
      refute inventory["isError"]
      assert inventory["structuredContent"]["kind"] == Atom.to_string(key)
      assert [%{"id" => id}] = inventory["structuredContent"]["entities"]
      assert id == entity.id

      arguments = Map.put(arguments, "id", entity.id)
      detail = Tools.GetBuildEntity.call(conn, arguments)
      refute detail["isError"]
      assert detail["structuredContent"]["entity"]["identity"] == entity.identity
      assert detail["structuredContent"]["analytics"]["total"]["observations"] == 1
      assert detail["structuredContent"]["analytics"]["total"]["duration_samples"] == 1
      assert detail["structuredContent"]["analytics"]["previous"]["duration_samples"] == 0
      schemas = Tools.GetBuildEntity.output_schema()["properties"]["analytics"]["properties"]

      for schema <- [schemas["total"], schemas["previous"], schemas["points"]["items"]] do
        assert schema["properties"]["duration_samples"]["minimum"] == 0
        refute "duration_samples" in schema["required"]
      end

      history = Tools.ListBuildEntityHistory.call(conn, arguments)
      refute history["isError"]
      assert [entry] = history["structuredContent"]["history"]
      assert entry["parent_id"] == observation.parent_id
      assert entry["execution_id"] == observation.execution_id
      assert JSON.decode!(hd(history["content"])["text"]) == history["structuredContent"]
    end
  end

  test "cache-action kinds are not exposed", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    FunWithFlags.enable(:build_entities, for_actor: project)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name}

    for kind <- ["bazel_cache_actions", "xcode_cache_actions"] do
      assert Tools.ListBuildEntities.call(conn, Map.put(args, "kind", kind))["isError"]
    end
  end

  test "a project that has not opted in gets an error before any query", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    reject(&BuildEntities.list/4)
    reject(&BuildEntities.get/4)

    args = %{
      "account_handle" => user.account.name,
      "project_handle" => project.name,
      "kind" => "gradle_tasks",
      "id" => UUIDv7.generate()
    }

    for {tool, args} <- [
          {Tools.ListBuildEntities, Map.delete(args, "id")},
          {Tools.GetBuildEntity, args},
          {Tools.ListBuildEntityHistory, args}
        ] do
      result = tool.call(conn, args)
      assert result["isError"]
      assert hd(result["content"])["text"] == "Build entities are not available for this project."
      refute Map.has_key?(result, "structuredContent")
    end
  end

  test "the flag is checked only after authorization", %{user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    stranger = AccountsFixtures.user_fixture()
    reject(&FeatureFlags.build_entities_enabled?/1)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name, "kind" => "gradle_tasks"}

    assert Tools.ListBuildEntities.call(%{assigns: %{current_subject: stranger}}, args)["isError"]
  end

  test "a kind from another toolchain is an error, not an empty result", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    FunWithFlags.enable(:build_entities, for_actor: project)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name, "kind" => "mix_files"}
    result = Tools.ListBuildEntities.call(conn, args)

    assert result["isError"]
    assert hd(result["content"])["text"] == "This kind is not available for this project's build toolchain."
  end

  test "query limits return a normal tool error rather than fabricated empty results", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    FunWithFlags.enable(:build_entities, for_actor: project)
    stub(BuildEntities, :list, fn _project_id, _system, _kind, _opts -> raise QueryLimitError end)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name, "kind" => "gradle_tasks"}
    result = Tools.ListBuildEntities.call(conn, args)

    assert result["isError"]
    assert hd(result["content"])["text"] == "The query exceeded analytics limits. Please try again later."
    refute Map.has_key?(result, "structuredContent")
  end

  test "authorization and project scope are checked for persistent IDs", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    FunWithFlags.enable(:build_entities, for_actor: project)
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)

    args = %{
      "account_handle" => user.account.name,
      "project_handle" => project.name,
      "kind" => "gradle_tasks",
      "id" => entity.id
    }

    stranger = AccountsFixtures.user_fixture()
    assert Tools.GetBuildEntity.call(%{assigns: %{current_subject: stranger}}, args)["isError"]

    other_project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    FunWithFlags.enable(:build_entities, for_actor: other_project)
    assert Tools.GetBuildEntity.call(conn, %{args | "project_handle" => other_project.name})["isError"]
    assert Tools.GetBuildEntity.call(conn, %{args | "id" => UUIDv7.generate()})["isError"]
    assert Tools.ListBuildEntityHistory.call(conn, Map.put(args, "after", "invalid"))["isError"]
  end
end
