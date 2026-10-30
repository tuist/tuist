defmodule Atlas.Automations.ResourcesTest do
  use Atlas.MCP.ToolCase

  import Atlas.AutomationsFixtures

  alias Atlas.Audit.Activity
  alias Atlas.Automations
  alias Atlas.Automations.Behavior
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Resources
  alias Atlas.Automations.Run

  setup do
    %{actor: insert_user!(%{scopes: ["automation:write"]}), other: insert_user!(%{scopes: ["automation:write"]})}
  end

  test "draft deletion requires its creator and refuses all published history", %{actor: actor, other: other} do
    attrs = %{
      "name" => "Draft",
      "source" => JSON.encode!(%{"steps" => [%{"id" => "value", "behavior" => "core.value", "inputs" => %{}}]})
    }

    {:ok, draft} = Automations.create_workflow(actor, attrs)
    assert {:error, :forbidden} = Resources.delete_workflow(other, draft.id, [])
    assert {:ok, %{deleted: true}} = Resources.delete_workflow(actor, draft.id, interface: "api")
    assert {:error, :not_found} = Automations.get_workflow(actor, draft.id)
    {workflow, revision} = workflow_fixture(actor)
    assert {:error, :workflow_in_use} = Resources.delete_workflow(actor, workflow.id, [])
    assert {:ok, %{id: id}} = Resources.get(actor, "revisions", revision.id)
    assert id == revision.id
    assert Repo.get_by!(Activity, target_id: draft.id, action: "automation.workflow.deleted").interface == "api"
  end

  test "configuration CRUD never changes published snapshots", %{actor: actor, other: other} do
    {:ok, behavior} = Automations.create_behavior(actor, %{"name" => "Value", "type" => "core.value"})

    {workflow, revision} =
      workflow_fixture(actor, [%{"id" => "value", "behavior" => behavior.id, "inputs" => %{"original" => true}}])

    assert {:error, :forbidden} = Resources.update_behavior(other, behavior.id, %{"name" => "Other"}, [])
    assert {:error, _} = Resources.update_behavior(actor, behavior.id, %{"type" => "missing"}, [])

    assert {:ok, _} =
             Resources.update_behavior(
               actor,
               behavior.id,
               %{"input_schema" => %{"type" => "object", "required" => ["new_field"]}},
               []
             )

    assert {:error, :forbidden} = Resources.delete_behavior(other, behavior.id, [])
    assert {:ok, _} = Resources.delete_behavior(actor, behavior.id, [])
    refute Repo.get(Behavior, behavior.id)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert {:ok, :ok} = Executor.advance(run.id)
    assert Repo.get!(Run, run.id).outputs == %{"value" => %{"original" => true}}
    assert {:ok, %{id: id}} = Resources.get(actor, "revisions", revision.id)
    assert id == revision.id
  end

  test "trigger update validates input/cron, preserves pinning and requires execution owner", %{
    actor: actor,
    other: other
  } do
    {workflow, revision} = workflow_fixture(actor)

    {:ok, %{trigger: trigger}} =
      Automations.create_trigger(actor, workflow.id, %{
        "name" => "Schedule",
        "kind" => "schedule",
        "cron" => "0 0 * * *"
      })

    assert {:error, :forbidden} = Resources.update_trigger(other, trigger.id, %{"name" => "Other"}, [])
    assert {:error, _} = Resources.update_trigger(actor, trigger.id, %{"cron" => "bad"}, [])

    assert {:ok, updated} =
             Resources.update_trigger(actor, trigger.id, %{"cron" => "0 12 * * *", "enabled" => false},
               interface: "mcp"
             )

    assert updated.cron == "0 12 * * *"
    refute updated.enabled
    assert updated.revision_id == revision.id
    assert {:error, :not_found} = Resources.get(actor, "webhooks", trigger.id)
    assert {:error, :invalid_trigger_kind} = Resources.rotate_trigger(actor, trigger.id, %{}, [])
    assert {:error, :forbidden} = Resources.delete_trigger(other, trigger.id, %{}, [])
    assert {:ok, _} = Resources.delete_trigger(actor, trigger.id, %{}, [])
  end

  test "rotation revokes the old credential and deletion preserves admitted executions", %{actor: actor} do
    {workflow, _} = workflow_fixture(actor)

    {:ok, %{trigger: trigger, secret: old}} =
      Automations.create_trigger(actor, workflow.id, %{"name" => "Hook", "kind" => "webhook"})

    {:ok, %{secret: fresh}} = Resources.rotate_trigger(actor, trigger.id, %{}, interface: "api")
    refute fresh == old
    assert {:error, :unauthorized} = Automations.webhook(trigger.id, old, "old", %{})
    assert {:ok, run} = Automations.webhook(trigger.id, fresh, "new", %{})
    assert {:ok, _} = Resources.delete_trigger(actor, trigger.id, %{}, [])
    assert {:error, :unauthorized} = Automations.webhook(trigger.id, fresh, "later", %{})
    assert Repo.get!(Run, run.id).revision_id == run.revision_id
    activity = Repo.get_by!(Activity, target_id: trigger.id, action: "automation.trigger.credential_rotated")
    refute JSON.encode!(activity.metadata) =~ fresh
    refute JSON.encode!(activity.metadata) =~ old
  end

  test "evidence reads are bounded and require a real parent", %{actor: actor} do
    {workflow, revision} = workflow_fixture(actor)
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)

    for kind <- ~w(attempts events) do
      assert {:ok, {items, meta}} = Resources.list(actor, kind, %{"run_id" => run.id, "page" => 1})
      assert items != [] && length(items) <= 20
      assert meta.page_size == 20
      assert {:error, :not_found} = Resources.list(actor, kind, %{"run_id" => Ecto.UUID.generate()})
    end

    assert {:ok, {[%{id: id}], _}} = Resources.list(actor, "revisions", %{"workflow_id" => workflow.id})
    assert id == revision.id
  end
end
