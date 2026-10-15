defmodule TuistTestSupport.Fixtures.BuildEntitiesFixtures do
  @moduledoc false

  alias Tuist.BuildEntities

  @identities %{
    gradle_tasks:
      {:gradle, "task",
       %{"root_project_name" => "app", "build_path" => ":", "task_path" => ":app:test", "task_type" => "Test"}},
    xcode_modules: {:xcode, "module", %{"project" => "App", "target" => "App"}},
    once_actions: {:once, "action", %{"target_id" => "app", "capability" => "build", "action_index" => "0"}},
    mix_files: {:mix, "file", %{"path" => "lib/app.ex"}},
    mix_modules: {:mix, "module", %{"module" => "App"}}
  }

  def entity_fixture(project, resource, attrs \\ []) do
    FunWithFlags.enable(:build_entities, for_actor: project)
    {system, kind, identity} = Map.fetch!(@identities, resource)

    observation =
      Map.merge(
        %{
          project_id: project.id,
          system: system,
          kind: kind,
          identity: identity,
          name: "Recorded compilation",
          parent_id: UUIDv7.generate(),
          execution_id: UUIDv7.generate(),
          status: "success",
          cache_status: "none",
          duration_ms: 120,
          observed_at: DateTime.add(DateTime.utc_now(), -300, :second),
          git_branch: "main",
          git_commit_sha: "abc123",
          is_ci: true
        },
        Map.new(attrs)
      )

    :ok = BuildEntities.record([observation])
    {entities, _meta} = BuildEntities.list(project.id, system, kind, search: observation.name)
    entity = Enum.find(entities, &(&1.identity == observation.identity))
    %{entity: entity, observation: observation}
  end
end
