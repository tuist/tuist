defmodule Tuist.BuildEntities.ExecutionScopeTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.BuildEntities
  alias TuistTestSupport.Fixtures.BuildEntitiesFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.BuildEntityResources

  test "dashboard duration statistics and scatter exclude timed cached and unexecuted actions" do
    project = ProjectsFixtures.project_fixture()
    %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, :once_actions)
    BuildEntitiesFixtures.entity_fixture(project, :once_actions, duration_ms: 0, status: "failure")
    BuildEntitiesFixtures.entity_fixture(project, :once_actions, duration_ms: 0, cache_status: "hit")
    BuildEntitiesFixtures.entity_fixture(project, :once_actions, duration_ms: 0, status: "skipped")
    opts = [execution_metrics_only: true]
    assert BuildEntities.inventory_analytics(project.id, :once, "action").total.duration_samples == 4
    total = BuildEntities.inventory_analytics(project.id, :once, "action", opts).total
    assert total.duration_samples == 2
    assert total.avg_duration_ms == 60
    {rows, _meta} = BuildEntities.list(project.id, :once, "action", opts)
    assert [row] = rows
    assert row.id == entity.id
    assert row.duration_samples == 2
    assert row.avg_duration_ms == 60
    scatter = BuildEntities.inventory_duration_scatter(project.id, :once, "action", opts)
    assert Enum.sort(Enum.map(scatter.rows, & &1.duration_ms)) == [0, 120]
  end

  for resource <- BuildEntityResources.dashboard_resources() do
    test "#{resource.key} cached outcomes do not become executed failure measurements" do
      resource = BuildEntityResources.fetch!(unquote(resource.key))
      project = ProjectsFixtures.project_fixture()
      BuildEntitiesFixtures.entity_fixture(project, resource.key, cache_status: "hit", status: "success")
      BuildEntitiesFixtures.entity_fixture(project, resource.key, cache_status: "hit_remote", status: "failure")
      public = BuildEntities.inventory_analytics(project.id, resource.system, resource.kind).total
      assert public.failures == 1
      assert public.outcome_samples == 2
      opts = [execution_metrics_only: true]
      scoped = BuildEntities.inventory_analytics(project.id, resource.system, resource.kind, opts).total
      assert scoped.entities == 1
      assert scoped.observations == 2
      assert scoped.executions == 0
      assert scoped.failures == 0
      assert scoped.outcome_samples == 0
      assert scoped.duration_samples == 0
      {rows, _meta} = BuildEntities.list(project.id, resource.system, resource.kind, opts)
      assert [row] = rows
      assert row.failures == 0
      assert row.duration_samples == 0
    end

    test "#{resource.key} execution-only reads preserve public history and native missing timing", _context do
      resource = BuildEntityResources.fetch!(unquote(resource.key))
      project = ProjectsFixtures.project_fixture()
      %{entity: entity} = BuildEntitiesFixtures.entity_fixture(project, resource.key)
      BuildEntitiesFixtures.entity_fixture(project, resource.key, duration_ms: nil, cache_status: "hit_remote")
      BuildEntitiesFixtures.entity_fixture(project, resource.key, duration_ms: nil, status: "unknown")
      BuildEntitiesFixtures.entity_fixture(project, resource.key, duration_ms: nil, status: "failure")

      {legacy, legacy_meta} = BuildEntities.history(project.id, resource.system, resource.kind, entity.id)
      assert length(legacy) == 4
      assert legacy_meta.total_count == 4
      {rows, meta} = BuildEntities.history(project.id, resource.system, resource.kind, entity.id, executions_only: true)

      expected =
        case resource.system do
          :xcode -> 1
          :mix -> 3
          _ -> 2
        end

      assert meta.total_count == expected
      assert length(rows) == expected
      refute Enum.any?(rows, &(&1.cache_status == "hit_remote"))
      metrics = BuildEntities.analytics(project.id, resource.system, resource.kind, entity.id, executions_only: true)
      assert metrics.total.observations == expected
      assert metrics.total.hits == 0
      assert metrics.total.duration_samples == 1
      assert BuildEntities.analytics(project.id, resource.system, resource.kind, entity.id).total.observations == 4

      assert %{rows: [%{duration_ms: 120}]} =
               BuildEntities.duration_scatter(project.id, resource.system, resource.kind, entity.id,
                 executions_only: true
               )
    end

    test "#{resource.key} replacement into a cache hit cannot resurrect an older execution", _context do
      resource = BuildEntityResources.fetch!(unquote(resource.key))
      project = ProjectsFixtures.project_fixture()
      %{entity: entity, observation: observation} = BuildEntitiesFixtures.entity_fixture(project, resource.key)
      corrected = Map.merge(observation, %{cache_status: "hit_remote", duration_ms: nil})
      :ok = BuildEntities.record([corrected], sync: true)
      {rows, meta} = BuildEntities.history(project.id, resource.system, resource.kind, entity.id, executions_only: true)
      assert rows == []
      assert meta.total_count == 0

      assert BuildEntities.analytics(project.id, resource.system, resource.kind, entity.id, executions_only: true).total.observations ==
               0

      assert BuildEntities.duration_scatter(project.id, resource.system, resource.kind, entity.id, executions_only: true).rows ==
               []

      assert {[record], _meta} = BuildEntities.history(project.id, resource.system, resource.kind, entity.id)
      assert record.cache_status == "hit_remote"
    end
  end
end
