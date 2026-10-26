defmodule Atlas.Automations.ListQueryTest do
  use Atlas.DataCase, async: true

  import Atlas.AutomationsFixtures
  import Atlas.MCP.ToolCase, only: [insert_user!: 1]

  alias Atlas.Automations
  alias Atlas.Automations.Approval
  alias Atlas.Automations.Behavior
  alias Atlas.Automations.ListQuery
  alias Atlas.Automations.Resources
  alias Atlas.Automations.Run
  alias Atlas.Automations.Trigger

  setup do
    actor = insert_user!(%{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    %{actor: actor, workflow: workflow, revision: revision}
  end

  test "trigger metadata filters, stable sorting and paging apply before Flop", %{
    actor: actor,
    workflow: workflow,
    revision: revision
  } do
    for kind <- ~w(schedule webhook) do
      rows =
        for n <- 1..24 do
          Repo.insert!(%Trigger{
            name: "Inventory #{String.pad_leading(to_string(n), 2, "0")}",
            kind: kind,
            revision_id: revision.id,
            execution_user_id: actor.id,
            cron: "0 9 * * 1",
            input: %{"private" => "private-trigger-payload"}
          })
        end

      Repo.insert!(%Trigger{
        name: "Paused",
        kind: kind,
        enabled: false,
        revision_id: revision.id,
        execution_user_id: actor.id
      })

      params = %{
        "status" => "enabled",
        "workflow" => workflow.name,
        "workflow_op" => "=~",
        "sort_by" => "name",
        "sort_order" => "asc"
      }

      assert {:ok, {first, meta}} = Automations.list_triggers(actor, kind, params)
      assert meta.total_count == 24
      assert Enum.map(first, & &1.id) == Enum.map(Enum.take(rows, 20), & &1.id)
      assert {:ok, {last, _}} = Automations.list_triggers(actor, kind, Map.put(params, "page", "2"))
      assert Enum.map(last, & &1.id) == Enum.map(Enum.drop(rows, 20), & &1.id)

      assert {:ok, {[paused], _}} =
               Automations.list_triggers(actor, kind, %{"status" => "enabled", "status_op" => "!="})

      refute paused.enabled
      assert {:ok, {[], _}} = Automations.list_triggers(actor, kind, %{"q" => "private-trigger-payload"})

      for q <- ["%", "_", "\\"] do
        assert {:ok, {[], _}} = Automations.list_triggers(actor, kind, %{"q" => q})
      end

      section = if kind == "schedule", do: "schedules", else: "webhooks"

      for field <- ListQuery.sort_fields(section) do
        assert {:ok, {_, _}} = Automations.list_triggers(actor, kind, %{"sort_by" => field, "sort_order" => "asc"})
      end

      assert {:ok, {_, _}} =
               Automations.list_triggers(actor, kind, %{
                 "q" => %{},
                 "status" => %{},
                 "workflow" => %{},
                 "sort_by" => "input",
                 "sort_order" => "sideways"
               })
    end

    assert {:ok, {_, meta}} = Resources.list(actor, "triggers", %{"status" => "paused"})
    assert meta.total_count == 2
  end

  test "webhook endpoint and cron are searchable metadata, credentials are not", %{actor: actor, revision: revision} do
    hook =
      Repo.insert!(%Trigger{
        name: "Endpoint",
        kind: "webhook",
        revision_id: revision.id,
        execution_user_id: actor.id,
        token_hash: "credential-hash-do-not-search"
      })

    assert {:ok, {[found], _}} =
             Automations.list_triggers(actor, "webhook", %{"q" => "/api/automation/hooks/#{hook.id}"})

    assert found.id == hook.id
    assert {:ok, {[], _}} = Automations.list_triggers(actor, "webhook", %{"q" => "credential-hash-do-not-search"})
  end

  test "workflow publication and effective language filters ignore source", %{actor: actor, workflow: workflow} do
    {:ok, draft} =
      Automations.create_workflow(actor, %{
        "name" => "JS draft",
        "language" => "javascript",
        "source" => "return {private: 'private-workflow-source'};"
      })

    assert {:ok, {[found], _}} = Automations.list_workflows(actor, %{"status" => "draft", "language" => "javascript"})
    assert found.id == draft.id
    assert {:ok, {[found], _}} = Automations.list_workflows(actor, %{"status" => "published", "language" => "json"})
    assert found.id == workflow.id
    assert {:ok, {[], _}} = Automations.list_workflows(actor, %{"q" => "private-workflow-source"})

    for field <- ListQuery.sort_fields("workflows") do
      assert {:ok, {_, _}} = Automations.list_workflows(actor, %{"sort_by" => field, "sort_order" => "asc"})
    end
  end

  test "saved configuration search never examines its configuration or schemas", %{actor: actor} do
    a =
      Repo.insert!(%Behavior{
        name: "Alpha configuration",
        type: "core.value",
        created_by_id: actor.id,
        configuration: %{"private" => "private-configuration"}
      })

    b = Repo.insert!(%Behavior{name: "Beta configuration", type: "tasks.create", created_by_id: actor.id})
    assert {:ok, {[found], _}} = Automations.list_behaviors(actor, %{"q" => "Alpha", "behavior_type" => "core.value"})
    assert found.id == a.id

    assert {:ok, {[found], _}} =
             Automations.list_behaviors(actor, %{"behavior_type" => "core.value", "behavior_type_op" => "!="})

    assert found.id == b.id
    assert {:ok, {[], _}} = Automations.list_behaviors(actor, %{"q" => "private-configuration"})

    for field <- ListQuery.sort_fields("behaviors") do
      assert {:ok, {_, _}} = Automations.list_behaviors(actor, %{"sort_by" => field, "sort_order" => "asc"})
    end
  end

  test "approval metadata and cancellation filter work without searching exact payloads", %{
    actor: actor,
    workflow: workflow,
    revision: revision
  } do
    reviewer = insert_user!(%{name: "Other reviewer", scopes: ["automation:write"]})
    run = Repo.insert!(%Run{revision_id: revision.id, initiated_by_id: actor.id})

    cancelled =
      Repo.insert!(%Approval{
        run_id: run.id,
        reviewer_id: actor.id,
        step_id: "review_cancelled",
        status: "cancelled",
        payload: %{"private" => "private-approval-payload"}
      })

    Repo.insert!(%Approval{
      run_id: run.id,
      reviewer_id: reviewer.id,
      step_id: "review_pending",
      status: "pending",
      payload: %{}
    })

    assert {:ok, {[found], _}} = Automations.list_approvals(actor, %{"q" => workflow.name, "status" => "cancelled"})
    assert found.id == cancelled.id
    assert {:ok, {[found], _}} = Automations.list_approvals(actor, %{"reviewer" => "Other", "reviewer_op" => "=~"})
    assert found.reviewer_id == reviewer.id

    assert {:ok, {[found], _}} =
             Automations.list_approvals(actor, %{
               "workflow" => workflow.name,
               "workflow_op" => "==",
               "status" => "cancelled",
               "status_op" => "!="
             })

    assert found.status == "pending"
    assert {:ok, {[], _}} = Automations.list_approvals(actor, %{"q" => "private-approval-payload"})
    assert {:ok, {[], _}} = Automations.list_approvals(actor, %{"q" => reviewer.email})

    for field <- ListQuery.sort_fields("approvals") do
      assert {:ok, {asc, _}} = Automations.list_approvals(actor, %{"sort_by" => field, "sort_order" => "asc"})
      assert {:ok, {desc, _}} = Automations.list_approvals(actor, %{"sort_by" => field, "sort_order" => "desc"})
      assert Enum.map(asc, & &1.id) == Enum.reverse(Enum.map(desc, & &1.id))
    end
  end
end
