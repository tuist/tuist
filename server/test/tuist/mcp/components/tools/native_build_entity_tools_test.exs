defmodule Tuist.MCP.Components.Tools.NativeBuildEntityToolsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.BuildEntities
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.MCP.Components.Tools
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BuildEntitiesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.BuildEntityResources

  @tools [
    {:gradle_tasks, Tools.ListGradleTasks, Tools.GetGradleTask, Tools.ListGradleTaskExecutions},
    {:xcode_cache_actions, Tools.ListXcodeCacheActions, Tools.GetXcodeCacheAction, Tools.ListXcodeCacheActionEvents},
    {:xcode_modules, Tools.ListXcodeModules, Tools.GetXcodeModule, Tools.ListXcodeModuleCacheEvents},
    {:bazel_cache_actions, Tools.ListBazelCacheActions, Tools.GetBazelCacheAction, Tools.ListBazelCacheActionEvents},
    {:once_actions, Tools.ListOnceActions, Tools.GetOnceAction, Tools.ListOnceActionExecutions},
    {:mix_files, Tools.ListMixFiles, Tools.GetMixFile, Tools.ListMixFileCompilations},
    {:mix_modules, Tools.ListMixModules, Tools.GetMixModule, Tools.ListMixModuleCompilations}
  ]

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{user: user, conn: %{assigns: %{current_subject: user}}}
  end

  for {key, inventory_tool, detail_tool, history_tool} <- @tools do
    test "#{key} return schema-valid native list, detail and history results", %{conn: conn, user: user} do
      {key, inventory_tool, detail_tool, history_tool} =
        unquote(Macro.escape({key, inventory_tool, detail_tool, history_tool}))

      resource = BuildEntityResources.fetch!(key)
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: resource.system)
      %{entity: entity, observation: observation} = BuildEntitiesFixtures.entity_fixture(project, key)
      arguments = %{"account_handle" => user.account.name, "project_handle" => project.name}

      inventory = inventory_tool.call(conn, arguments)
      refute inventory["isError"]
      assert [%{"id" => id}] = inventory["structuredContent"][to_string(resource.plural)]
      assert id == entity.id
      refute Map.has_key?(inventory["structuredContent"], "build_entities")

      arguments = Map.put(arguments, to_string(resource.id_param), entity.id)
      detail = detail_tool.call(conn, arguments)
      refute detail["isError"]
      assert detail["structuredContent"][to_string(resource.singular)]["identity"] == entity.identity
      assert detail["structuredContent"]["analytics"]["total"]["observations"] == 1
      assert detail["structuredContent"]["analytics"]["total"]["duration_samples"] == 1
      assert detail["structuredContent"]["analytics"]["previous"]["duration_samples"] == 0
      schemas = detail_tool.output_schema()["properties"]["analytics"]["properties"]

      for schema <- [schemas["total"], schemas["previous"], schemas["points"]["items"]] do
        assert schema["properties"]["duration_samples"]["minimum"] == 0
        refute "duration_samples" in schema["required"]
      end

      legacy_analytics =
        detail["structuredContent"]["analytics"]
        |> Map.update!("total", &Map.delete(&1, "duration_samples"))
        |> Map.update!("previous", &Map.delete(&1, "duration_samples"))
        |> Map.update!("points", &Enum.map(&1, fn point -> Map.delete(point, "duration_samples") end))

      legacy_content = Map.put(detail["structuredContent"], "analytics", legacy_analytics)
      assert :ok == ExJsonSchema.Validator.validate(detail_tool.resolved_output_schema(), legacy_content)

      history = history_tool.call(conn, arguments)
      refute history["isError"]
      assert [entry] = history["structuredContent"][to_string(resource.history_key)]
      assert entry["parent_id"] == observation.parent_id
      assert entry["execution_id"] == observation.execution_id
      assert JSON.decode!(hd(history["content"])["text"]) == history["structuredContent"]
    end
  end

  test "query limits return a normal tool error rather than fabricated empty results", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    stub(BuildEntities, :list, fn _project_id, _system, _kind, _opts -> raise QueryLimitError end)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name}
    result = Tools.ListGradleTasks.call(conn, args)

    assert result["isError"]
    assert hd(result["content"])["text"] == "The query exceeded analytics limits. Please try again later."
    refute Map.has_key?(result, "structuredContent")
  end

  test "authorization and project scope are checked for persistent IDs", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :gradle_tasks)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name, "task_id" => entity.id}

    stranger = AccountsFixtures.user_fixture()
    assert Tools.GetGradleTask.call(%{assigns: %{current_subject: stranger}}, args)["isError"]

    other_project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :gradle)
    assert Tools.GetGradleTask.call(conn, %{args | "project_handle" => other_project.name})["isError"]
    assert Tools.ListGradleTaskExecutions.call(conn, Map.put(args, "after", "invalid"))["isError"]
  end
end
