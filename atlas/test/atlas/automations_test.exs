defmodule Atlas.AutomationsTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.AutomationsFixtures
  import Atlas.MCP.ToolCase, only: [insert_user!: 1]

  alias Atlas.Authorization.Roles
  alias Atlas.Automations
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Behavior
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Plan
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Run
  alias Atlas.Automations.Trigger
  alias Atlas.Automations.Workflow
  alias Atlas.Repo
  alias Atlas.Tasks

  setup do
    %{actor: insert_user!(%{scopes: ["automation:write"]})}
  end

  test "domain boundaries deny unassigned callers and read-only authors", %{actor: actor} do
    stranger = insert_user!(%{})
    reader = insert_user!(%{scopes: ["automation:read"]})
    {workflow, _} = workflow_fixture(actor)
    assert {:error, :forbidden} = Automations.list_workflows(stranger)
    assert {:error, :forbidden} = Automations.get_workflow(stranger, workflow.id)
    assert {:error, :forbidden} = Automations.create_workflow(reader, %{})
    assert {:error, :forbidden} = Automations.save_workflow_version(reader, nil, %{})
    assert {:error, :forbidden} = Automations.save_workflow_version(reader, workflow.id, %{})
    assert {:error, :forbidden} = Automations.publish_workflow(reader, workflow.id)
    assert {:error, :forbidden} = Automations.run_workflow(reader, workflow.id, %{})
    assert {:error, :forbidden} = Automations.validate_workflow(reader, workflow.id)
    assert {:ok, {[_], _meta}} = Automations.list_workflows(reader)
  end

  test "publishing pins the plan while drafts and behaviors may change", %{actor: actor} do
    {:ok, behavior} = Automations.create_behavior(actor, %{"name" => "Identity", "type" => "core.value"})

    {workflow, revision} =
      workflow_fixture(actor, [%{"id" => "value", "behavior" => behavior.id, "inputs" => %{"text" => "original"}}])

    behavior |> Ecto.Changeset.change(output_schema: %{"type" => "object", "required" => ["missing"]}) |> Repo.update!()
    assert {:ok, _} = Automations.update_workflow(actor, workflow.id, %{"source" => "not json"})
    assert {:error, _} = Automations.publish_workflow(actor, workflow.id)
    assert {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert run.revision_id == revision.id
    assert {:ok, _} = Executor.advance(run.id)
    assert {:ok, _} = Executor.advance(run.id)
    assert Repo.get!(Run, run.id).outputs == %{"value" => %{"text" => "original"}}
    assert Repo.get!(Run, run.id).status == "succeeded"
    assert Repo.get!(Behavior, behavior.id).output_schema["required"] == ["missing"]
  end

  test "saving a version creates a ready workflow and preserves pinned runs and triggers", %{actor: actor} do
    source = JSON.encode!(%{"steps" => [%{"id" => "value", "behavior" => "core.value", "inputs" => %{}}]})
    assert {:ok, workflow} = Automations.save_workflow_version(actor, nil, %{"name" => "Versioned", "source" => source})
    first = workflow.published_revision
    assert first.number == 1
    assert first.source == source
    assert {:ok, old_run} = Automations.run_workflow(actor, workflow.id, %{})

    assert {:ok, %{trigger: trigger}} =
             Automations.create_trigger(actor, workflow.id, %{"name" => "Hook", "kind" => "webhook"})

    updated_source = JSON.encode!(%{"steps" => [%{"id" => "updated", "behavior" => "core.value", "inputs" => %{}}]})

    assert {:ok, updated} =
             Automations.save_workflow_version(actor, workflow.id, %{"source" => updated_source},
               expected_revision_id: first.id
             )

    assert updated.published_revision.number == 2
    assert updated.published_revision.source == updated_source
    assert Repo.get!(Revision, first.id).source == source
    assert Repo.get!(Run, old_run.id).revision_id == first.id
    assert Repo.get!(Trigger, trigger.id).revision_id == first.id
    assert {:ok, new_run} = Automations.run_workflow(actor, workflow.id, %{})
    assert new_run.revision_id == updated.published_revision_id
  end

  test "invalid version saves leave no workflow or changes behind", %{actor: actor} do
    assert {:error, _} = Automations.save_workflow_version(actor, nil, %{"name" => "Invalid", "source" => "{"})
    assert Repo.aggregate(Workflow, :count) == 0
    {workflow, first} = workflow_fixture(actor)

    assert {:error, _} =
             Automations.save_workflow_version(actor, workflow.id, %{"name" => "Not saved", "source" => "{}"})

    assert Repo.get!(Workflow, workflow.id).name == workflow.name
    assert Repo.get!(Workflow, workflow.id).source == workflow.source
    assert Repo.get!(Workflow, workflow.id).published_revision_id == first.id
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "a failed publication rolls back definition changes", %{actor: actor} do
    {workflow, first} = workflow_fixture(actor)

    stub(Repo, :insert!, fn
      %Revision{} -> raise "publication failed"
      record -> Mimic.call_original(Repo, :insert!, [record])
    end)

    assert_raise RuntimeError, "publication failed", fn ->
      Automations.save_workflow_version(actor, workflow.id, %{"name" => "Not committed"})
    end

    assert Repo.get!(Workflow, workflow.id).name == workflow.name
    assert Repo.get!(Workflow, workflow.id).published_revision_id == first.id
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "stale editors cannot replace a newer published version", %{actor: actor} do
    {workflow, first} = workflow_fixture(actor)
    assert {:ok, updated} = Automations.save_workflow_version(actor, workflow.id, %{"name" => "Newer"})

    assert {:error, :workflow_changed} =
             Automations.save_workflow_version(actor, workflow.id, %{"name" => "Stale"}, expected_revision_id: first.id)

    assert Repo.get!(Workflow, workflow.id).name == "Newer"
    assert Repo.get!(Workflow, workflow.id).published_revision_id == updated.published_revision_id
    assert Repo.aggregate(Revision, :count) == 2
  end

  test "changes made during compilation are not overwritten", %{actor: actor} do
    {workflow, first} = workflow_fixture(actor)

    stub(Plan, :compile, fn plan ->
      {:ok, _} = Automations.update_workflow(actor, workflow.id, %{"name" => "Concurrent change"})
      Mimic.call_original(Plan, :compile, [plan])
    end)

    assert {:error, :workflow_changed} = Automations.save_workflow_version(actor, workflow.id, %{"name" => "Stale"})
    assert Repo.get!(Workflow, workflow.id).name == "Concurrent change"
    assert Repo.get!(Workflow, workflow.id).published_revision_id == first.id
    assert Repo.aggregate(Revision, :count) == 1
  end

  test "unpublished workflows cannot run or bind triggers", %{actor: actor} do
    {:ok, workflow} = Automations.create_workflow(actor, %{"name" => "Draft", "source" => "{}"})
    assert {:error, :not_published} = Automations.run_workflow(actor, workflow.id, %{})

    assert {:error, :not_published} =
             Automations.create_trigger(actor, workflow.id, %{"name" => "Hook", "kind" => "webhook"})
  end

  test "task actions and durable progress commit together and duplicate delivery is harmless", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        %{"id" => "context", "behavior" => "core.value", "inputs" => %{"title" => %{"$ref" => "input.title"}}},
        %{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"title" => %{"$ref" => "steps.context.title"}}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{"title" => "Review build"})
    for _ <- 1..5, do: assert({:ok, _} = Executor.advance(run.id))
    assert [%{title: "Review build"}] = Tasks.list_tasks(assignee_id: actor.id)
    assert {:ok, result} = Automations.get_run(actor, run.id)
    assert result.status == "succeeded"
    assert length(result.attempts) == 2
    assert Enum.all?(result.attempts, &(&1.executor == "local"))
  end

  test "approvals suspend durably and only the assigned reviewer can release the exact payload", %{actor: actor} do
    reviewer = insert_user!(%{scopes: ["automation:write"]})

    {workflow, _} =
      workflow_fixture(actor, [
        %{
          "id" => "review",
          "type" => "approval",
          "reviewer_id" => reviewer.id,
          "inputs" => %{"title" => "Approved task"}
        },
        %{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"$ref" => "steps.review"}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert {:ok, _} = Executor.advance(run.id)
    assert Repo.get!(Run, run.id).status == "waiting_approval"
    approval = Repo.get_by!(Approval, run_id: run.id)
    assert {:error, :decision_not_allowed} = Automations.decide_approval(actor, approval.id, "approved")
    assert Tasks.list_tasks(assignee_id: actor.id) == []
    assert {:ok, _} = Automations.decide_approval(reviewer, approval.id, "approved")
    assert {:error, :decision_not_allowed} = Automations.decide_approval(reviewer, approval.id, "approved")
    for _ <- 1..2, do: Executor.advance(run.id)
    assert [%{title: "Approved task"}] = Tasks.list_tasks(assignee_id: actor.id)
    assert Repo.get!(Run, run.id).outputs["review"] == approval.payload
  end

  test "rejection prevents all downstream actions", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        %{"id" => "review", "type" => "approval", "reviewer_id" => actor.id, "inputs" => %{"title" => "Do not create"}},
        %{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"$ref" => "steps.review"}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)
    approval = Repo.get_by!(Approval, run_id: run.id)
    assert {:ok, _} = Automations.decide_approval(actor, approval.id, "rejected")
    Executor.advance(run.id)
    assert Repo.get!(Run, run.id).status == "rejected"
    assert Tasks.list_tasks(assignee_id: actor.id) == []
  end

  test "revocation between steps stops execution", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        %{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"title" => "No authority"}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Roles.set_user_roles(actor, [])
    Executor.advance(run.id)
    assert Repo.get!(Run, run.id).status == "failed"
    assert Tasks.list_tasks(assignee_id: actor.id) == []
  end

  test "owners can retry from committed progress without repeating earlier effects", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        %{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"title" => "Once"}},
        %{"id" => "finish", "behavior" => "core.value", "inputs" => %{}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)

    Repo.get!(Run, run.id)
    |> Ecto.Changeset.change(status: "failed", last_error: "Transient host failure")
    |> Repo.update!()

    other = insert_user!(%{scopes: ["automation:write"]})
    assert {:error, :forbidden} = Automations.control_run(other, run.id, "retry")
    assert {:ok, _} = Automations.control_run(actor, run.id, "retry")
    for _ <- 1..3, do: Executor.advance(run.id)
    assert [%{title: "Once"}] = Tasks.list_tasks(assignee_id: actor.id)
    assert Repo.get!(Run, run.id).status == "succeeded"
  end

  test "cancelling a suspended run closes its gate and prevents later approval", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [%{"id" => "review", "type" => "approval", "reviewer_id" => actor.id, "inputs" => %{}}])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)
    approval = Repo.get_by!(Approval, run_id: run.id)
    assert {:ok, _} = Automations.control_run(actor, run.id, "cancel")
    assert Repo.get!(Approval, approval.id).status == "cancelled"
    assert {:error, :decision_not_allowed} = Automations.decide_approval(actor, approval.id, "approved")
    Executor.advance(run.id)
    assert Repo.get!(Run, run.id).status == "cancelled"
  end

  test "missing references fail visibly rather than passing blank values", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        %{"id" => "task", "behavior" => "tasks.create", "inputs" => %{"title" => %{"$ref" => "input.missing"}}}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    Executor.advance(run.id)
    assert Repo.get!(Run, run.id).status == "failed"
    assert Tasks.list_tasks(assignee_id: actor.id) == []
  end

  test "webhook credentials are hashed, deduplicated, and disabled immediately", %{actor: actor} do
    {workflow, revision} = workflow_fixture(actor)

    {:ok, %{trigger: hook, secret: secret}} =
      Automations.create_trigger(actor, workflow.id, %{"name" => "Hook", "kind" => "webhook"})

    assert hook.token_hash == :crypto.hash(:sha256, secret)
    refute inspect(hook) =~ secret
    assert hook.revision_id == revision.id
    assert {:error, :unauthorized} = Automations.webhook(hook.id, "wrong", "one", %{})
    assert {:error, :unauthorized} = Automations.webhook(hook.id, secret, "", %{})
    assert {:ok, first} = Automations.webhook(hook.id, secret, "one", %{})
    assert {:ok, duplicate} = Automations.webhook(hook.id, secret, "one", %{})
    assert first.id == duplicate.id
    assert {:ok, _} = Automations.set_trigger_enabled(actor, hook.id, false)
    assert {:error, :unauthorized} = Automations.webhook(hook.id, secret, "two", %{})
  end

  test "schedules coalesce missed occurrences and skip overlap", %{actor: actor} do
    {workflow, _} = workflow_fixture(actor)

    {:ok, %{trigger: trigger}} =
      Automations.create_trigger(actor, workflow.id, %{
        "name" => "Every minute",
        "kind" => "schedule",
        "cron" => "* * * * *"
      })

    trigger |> Ecto.Changeset.change(next_run_at: ~U[2020-01-01 00:00:00Z]) |> Repo.update!()
    assert :ok = Automations.schedule_due()
    assert Repo.aggregate(Run, :count) == 1
    assert DateTime.after?(Repo.get!(Trigger, trigger.id).next_run_at, Automations.now())
    trigger |> Ecto.Changeset.change(next_run_at: ~U[2020-01-02 00:00:00Z]) |> Repo.update!()
    Automations.schedule_due()
    assert Repo.aggregate(Run, :count) == 1
  end

  test "impossible or reboot schedules are rejected without computing an unbounded next date", %{actor: actor} do
    {workflow, _} = workflow_fixture(actor)

    for cron <- ["0 0 31 2 *", "@reboot", "invalid"] do
      assert {:error, %Ecto.Changeset{}} =
               Automations.create_trigger(actor, workflow.id, %{
                 "name" => "Invalid",
                 "kind" => "schedule",
                 "cron" => cron
               })
    end
  end

  test "schemas cannot fetch remote references and task effects retain their output contract", %{actor: actor} do
    assert {:error, _} =
             Automations.create_behavior(actor, %{
               "name" => "Remote",
               "type" => "core.value",
               "input_schema" => %{"type" => "object", "$ref" => "https://example.org/schema"}
             })

    assert {:error, _} =
             Automations.create_behavior(actor, %{
               "name" => "Task",
               "type" => "tasks.create",
               "output_schema" => %{"type" => "object", "required" => ["impossible"]}
             })
  end
end
