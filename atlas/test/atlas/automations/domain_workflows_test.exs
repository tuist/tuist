defmodule Atlas.Automations.DomainWorkflowsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  import Atlas.AutomationsFixtures

  alias Atlas.Audit.Activity
  alias Atlas.Authorization
  alias Atlas.Authorization.Roles
  alias Atlas.Automations
  alias Atlas.Automations.Catalog
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Native
  alias Atlas.Automations.Plan
  alias Atlas.Automations.Resources
  alias Atlas.Automations.Run
  alias Atlas.MCP.Tools.CreateNote
  alias Atlas.Notes
  alias Atlas.Notes.Note
  alias Atlas.Search.Record
  alias Atlas.Tasks

  setup do
    %{actor: insert_user!(%{scopes: Authorization.all_scopes()})}
  end

  test "complete task contract v2 composes with update/get/complete and v1 stays pinned", %{actor: actor} do
    {workflow, _} =
      workflow_fixture(actor, [
        step("create", "tasks.create@2", %{"title" => "Review", "assignee_id" => actor.id}),
        step("edit", "tasks.update@1", %{"task_id" => ref("steps.create.task.id"), "title" => "Reviewed"}),
        step("read", "tasks.get@1", %{"id" => ref("steps.edit.task.id")}),
        step("finish", "tasks.complete@1", %{"task_id" => ref("steps.read.task.id")})
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert %Run{status: "succeeded", outputs: outputs} = drain(run.id)
    assert outputs["finish"]["task"]["status"] == "completed"
    id = outputs["create"]["task"]["id"]
    assert Tasks.get_task(id).title == "Reviewed"
    assert Repo.get_by!(Activity, target_id: id, action: "task.created").interface == "worker"
    {:ok, old} = Catalog.builtin("tasks.create")
    assert {:ok, %{"task_id" => _, "title" => "Legacy"}} = Catalog.execute(old, %{"title" => "Legacy"}, actor)
  end

  test "notes CRUD pauses for an exact step/version/input approval before deletion", %{actor: actor} do
    target = %{"id" => ref("steps.read.note.id")}

    {workflow, revision} =
      workflow_fixture(actor, [
        step("create", "notes.create@1", %{"content" => "# Original\nBody"}),
        step("edit", "notes.update@1", %{"note_id" => ref("steps.create.note.id"), "content" => "# Edited\nBody"}),
        step("read", "notes.get@1", %{"note_id" => ref("steps.edit.note.id")}),
        review(actor, "delete", "notes.delete", target),
        step("delete", "notes.delete@1", target)
      ])

    assert revision.plan["read_permissions"] == ["notes:read"]
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert %Run{status: "waiting_approval", outputs: outputs} = drain(run.id)
    id = outputs["read"]["note"]["id"]
    assert Notes.get_note(id).title == "Edited"
    {:ok, {[approval], _}} = Automations.list_approvals(actor)

    assert approval.payload == %{
             "behavior" => "notes.delete",
             "version" => 1,
             "step_id" => "delete",
             "input" => %{"id" => id}
           }

    assert {:ok, _} = Automations.decide_approval(actor, approval.id, "approved")
    assert %Run{status: "succeeded"} = drain(run.id)
    refute Notes.get_note(id)
  end

  test "approval for another step or payload cannot authorize a destructive effect", %{actor: actor} do
    {:ok, note} = Notes.create_note(%{"content" => "# Keep"}, actor)
    target = %{"id" => note.id}

    {workflow, _} =
      workflow_fixture(actor, [
        review(actor, "another_step", "notes.delete", target),
        step("delete", "notes.delete@1", target)
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    drain(run.id)
    {:ok, {[approval], _}} = Automations.list_approvals(actor)
    Automations.decide_approval(actor, approval.id, "approved")
    assert %Run{status: "failed"} = drain(run.id)
    assert Notes.get_note(note.id)
  end

  test "publication rejects literal contract errors, nonexistent output paths and incompatible references" do
    assert {:error, _} = Plan.compile(%{"steps" => [step("bad", "notes.create@1", %{"wrong" => true})]})
    first = step("first", "tasks.create@2", %{"title" => "Task"})

    assert {:error, _} =
             Plan.compile(%{
               "steps" => [first, step("next", "notes.get@1", %{"note_id" => ref("steps.first.task.removed_field")})]
             })

    assert {:error, _} =
             Plan.compile(%{"steps" => [first, step("next", "notes.get@1", %{"note_id" => ref("steps.first.task")})]})
  end

  test "current domain grants are checked at admission and again at the action", %{actor: _actor} do
    actor = insert_user!(%{scopes: ["automation:write", "notes:write"]})
    {workflow, _} = workflow_fixture(actor, [step("create", "notes.create@1", %{"content" => "# Forbidden"})])
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    [role] = Roles.list_roles_for_user(actor)
    {:ok, _} = Roles.update_role(role, %{scopes: ["automation:write", "notes:read"]})
    assert %Run{status: "failed"} = drain(run.id)
    assert Notes.list_notes() == []
    assert {:error, :forbidden} = Automations.run_workflow(actor, workflow.id, %{})
  end

  test "domain outputs cannot be read through automation, evidence, analytics or native bypasses", %{actor: actor} do
    {workflow, revision} = workflow_fixture(actor, [step("create", "notes.create@1", %{"content" => "# Private data"})])
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    drain(run.id)
    {:ok, execution} = Automations.get_run(actor, run.id)
    attempt = hd(execution.attempts)
    reader = insert_user!(%{scopes: ["automation:read"]})

    for {kind, id} <- [
          {"workflows", workflow.id},
          {"revisions", revision.id},
          {"executions", run.id},
          {"attempts", attempt.id}
        ] do
      assert {:error, :not_found} = Resources.get(reader, kind, id)
    end

    assert {:ok, {[], _}} = Automations.list_runs(reader)
    assert {:ok, {[], _}} = Automations.list_workflows(reader)
    assert {:ok, %{total: %{executions: 0}}} = Automations.execution_analytics(reader)
    assert {:error, :not_found} = Native.result(reader, run.id)
    assert {:error, :not_found} = Native.execution(reader, run.id)
    reader = insert_user!(%{scopes: ["automation:read", "notes:read"]})
    assert {:ok, _} = Automations.get_run(reader, run.id)
    assert {:ok, _} = Native.result(reader, run.id)
  end

  test "invalid adapter output rolls back the local effect, search record and progress", %{actor: actor} do
    stub(CreateNote, :execute, fn _conn, args ->
      {:ok, _} = Notes.create_note(args, actor)
      {:ok, %{note: %{id: 123}}}
    end)

    {workflow, _} = workflow_fixture(actor, [step("create", "notes.create@1", %{"content" => "# Must roll back"})])
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert %Run{status: "failed", cursor: 0, outputs: %{}} = drain(run.id)
    assert Repo.aggregate(Note, :count) == 0
    assert Repo.aggregate(Record, :count) == 0
    assert Repo.aggregate(from(a in Activity, where: a.action == "note.created"), :count) == 0
    {:ok, execution} = Automations.get_run(actor, run.id)
    assert hd(execution.attempts).status == "failed"
    stub(CreateNote, :execute, &Mimic.call_original(CreateNote, :execute, [&1, &2]))
    assert {:ok, _} = Automations.control_run(actor, run.id, "retry")
    assert %Run{status: "succeeded"} = drain(run.id)
    assert Repo.aggregate(Note, :count) == 1
    assert Repo.aggregate(Record, :count) == 1
  end

  test "assigned reviewers still need the captured domain's read permission", %{actor: actor} do
    reviewer = insert_user!(%{scopes: ["automation:write"]})

    {workflow, _} =
      workflow_fixture(actor, [
        step("create", "notes.create@1", %{"content" => "# Private review"}),
        %{"id" => "review", "type" => "approval", "reviewer_id" => reviewer.id, "inputs" => ref("steps.create")}
      ])

    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert %Run{status: "waiting_approval"} = drain(run.id)
    {:ok, {[approval], _}} = Automations.list_approvals(actor)
    assert {:ok, {[], _}} = Automations.list_approvals(reviewer)
    assert {:error, :not_found} = Resources.get(reviewer, "approvals", approval.id)
    assert {:error, :not_found} = Native.approval(reviewer, approval.id)
    assert {:error, :not_found} = Automations.decide_approval(reviewer, approval.id, "approved")
  end

  test "oversized outputs also roll back before encoding a response", %{actor: actor} do
    stub(CreateNote, :execute, fn _conn, args ->
      {:ok, _} = Notes.create_note(args, actor)
      {:ok, %{note: %{content: String.duplicate("x", 65_537)}}}
    end)

    {workflow, _} = workflow_fixture(actor, [step("create", "notes.create@1", %{"content" => "# Must roll back"})])
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert %Run{status: "failed", cursor: 0} = drain(run.id)
    assert Notes.list_notes() == []
  end

  test "saved domain configurations pin registered contracts and reject schema replacement", %{actor: actor} do
    {:ok, saved} = Automations.create_behavior(actor, %{"name" => "Create note", "type" => "notes.create@1"})
    {:ok, entry} = DomainRegistry.fetch("notes.create@1")
    assert saved.input_schema == entry["input_schema"]

    assert {:error, _} =
             Resources.update_behavior(
               actor,
               saved.id,
               %{"input_schema" => %{"type" => "object", "required" => ["different"]}},
               []
             )

    {workflow, _} = workflow_fixture(actor, [step("create", saved.id, %{"content" => "# Snapshot"})])
    Resources.delete_behavior(actor, saved.id, [])
    {:ok, run} = Automations.run_workflow(actor, workflow.id, %{})
    assert %Run{status: "succeeded"} = drain(run.id)
  end

  test "all platform areas have working bounded read behaviors", %{actor: actor} do
    account = insert_account!()

    calls = [
      {"accounts.list", %{}},
      {"tasks.list", %{}},
      {"notes.list", %{}},
      {"assets.list", %{}},
      {"insurance.policies.list", %{}},
      {"engineering.projects.list", %{}},
      {"finance.accounts.list", %{}},
      {"documents.list", %{}},
      {"contracts.templates.list", %{}},
      {"letters.for_account", %{"account_id" => account.id}},
      {"gtm.email.subscribers.list", %{}},
      {"support.threads.list", %{}},
      {"audit.activities.list", %{}},
      {"briefs.list", %{}},
      {"licenses.list", %{}},
      {"inference.providers.list", %{}},
      {"users.list", %{}},
      {"integrations.github_apps.list", %{}}
    ]

    for {name, input} <- calls do
      {:ok, behavior} = Catalog.builtin(name)
      result = Catalog.execute(behavior, input, actor)
      assert match?({:ok, _}, result), "#{name}: #{inspect(result)}"
      assert {:ok, output} = result
      assert is_map(output)
    end
  end

  defp step(id, behavior, input), do: %{"id" => id, "behavior" => behavior, "inputs" => input}
  defp ref(path), do: %{"$ref" => path}

  defp review(actor, target, behavior, input),
    do: %{
      "id" => "review",
      "type" => "approval",
      "reviewer_id" => actor.id,
      "inputs" => %{"behavior" => behavior, "version" => 1, "step_id" => target, "input" => input}
    }

  defp drain(id, remaining \\ 40)

  defp drain(id, remaining) when remaining > 0 do
    run = Repo.get!(Run, id)

    if run.status in ~w(succeeded failed cancelled rejected waiting_approval) do
      run
    else
      assert {:ok, _} = Executor.advance(id)
      drain(id, remaining - 1)
    end
  end
end
