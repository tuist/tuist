defmodule Atlas.Automations.Interfaces do
  @moduledoc "The shared API/MCP operation inventory and primitive lifecycle contract."

  alias Atlas.MCP.Tools.ControlAutomationExecution
  alias Atlas.MCP.Tools.CreateAutomationBehavior
  alias Atlas.MCP.Tools.CreateAutomationTrigger
  alias Atlas.MCP.Tools.DecideAutomationApproval
  alias Atlas.MCP.Tools.DeleteAutomationBehavior
  alias Atlas.MCP.Tools.DeleteAutomationTrigger
  alias Atlas.MCP.Tools.DeleteAutomationWorkflow
  alias Atlas.MCP.Tools.GetAutomationAnalytics
  alias Atlas.MCP.Tools.GetAutomationExecution
  alias Atlas.MCP.Tools.GetAutomationExecutionTrace
  alias Atlas.MCP.Tools.GetAutomationRecord
  alias Atlas.MCP.Tools.GetAutomationWorkflow
  alias Atlas.MCP.Tools.ListAutomationRecords
  alias Atlas.MCP.Tools.ListAutomationTypes
  alias Atlas.MCP.Tools.PublishAutomationWorkflow
  alias Atlas.MCP.Tools.RotateAutomationWebhookCredential
  alias Atlas.MCP.Tools.RunAutomationWorkflow
  alias Atlas.MCP.Tools.SaveAutomationWorkflow
  alias Atlas.MCP.Tools.SetAutomationTriggerEnabled
  alias Atlas.MCP.Tools.UpdateAutomationBehavior
  alias Atlas.MCP.Tools.UpdateAutomationTrigger
  alias Atlas.MCP.Tools.UpdateAutomationWorkflow
  alias Atlas.MCP.Tools.ValidateAutomationWorkflow

  @operations [
    {:catalog, :read, :get, "/types", ListAutomationTypes, "list_automation_types"},
    {:list, :read, :get, "/records", ListAutomationRecords, "list_automation_records"},
    {:get_record, :read, :get, "/records/:kind/:id", GetAutomationRecord, "get_automation_record"},
    {:get_workflow, :read, :get, "/workflows/:id", GetAutomationWorkflow, "get_automation_workflow"},
    {:get_run, :read, :get, "/executions/:id", GetAutomationExecution, "get_automation_execution"},
    {:trace, :read, :get, "/executions/:id/trace", GetAutomationExecutionTrace, "get_automation_execution_trace"},
    {:analytics, :read, :get, "/analytics", GetAutomationAnalytics, "get_automation_analytics"},
    {:save, :write, :post, "/workflows", SaveAutomationWorkflow, "save_automation_workflow"},
    {:update_workflow, :write, :patch, "/workflows/:id", UpdateAutomationWorkflow, "update_automation_workflow"},
    {:delete_workflow, :write, :delete, "/workflows/:id", DeleteAutomationWorkflow, "delete_automation_workflow"},
    {:validate, :write, :post, "/workflows/:id/validate", ValidateAutomationWorkflow, "validate_automation_workflow"},
    {:publish, :write, :post, "/workflows/:id/publish", PublishAutomationWorkflow, "publish_automation_workflow"},
    {:run, :write, :post, "/workflows/:id/run", RunAutomationWorkflow, "run_automation_workflow"},
    {:behavior, :write, :post, "/behaviors", CreateAutomationBehavior, "create_automation_behavior"},
    {:update_behavior, :write, :patch, "/behaviors/:id", UpdateAutomationBehavior, "update_automation_behavior"},
    {:delete_behavior, :write, :delete, "/behaviors/:id", DeleteAutomationBehavior, "delete_automation_behavior"},
    {:trigger, :write, :post, "/triggers", CreateAutomationTrigger, "create_automation_trigger"},
    {:update_trigger, :write, :patch, "/triggers/:id", UpdateAutomationTrigger, "update_automation_trigger"},
    {:delete_trigger, :write, :delete, "/triggers/:id", DeleteAutomationTrigger, "delete_automation_trigger"},
    {:rotate_trigger, :write, :post, "/triggers/:id/rotate-credential", RotateAutomationWebhookCredential,
     "rotate_automation_webhook_credential"},
    {:toggle, :write, :post, "/triggers/:id/enabled", SetAutomationTriggerEnabled, "set_automation_trigger_enabled"},
    {:control, :write, :post, "/executions/:id/control", ControlAutomationExecution, "control_automation_execution"},
    {:decide, :write, :post, "/approvals/:id/decision", DecideAutomationApproval, "decide_automation_approval"}
  ]

  @primitives [
    %{
      kind: "types",
      collection: "types",
      mutable: false,
      lifecycle: "Registered in trusted code; read-only over API/MCP."
    },
    %{
      kind: "workflows",
      collection: "workflows",
      mutable: true,
      lifecycle:
        "Create/edit drafts or publish new versions; only creator-owned drafts without revisions may be deleted."
    },
    %{
      kind: "behaviors",
      collection: "behaviors",
      mutable: true,
      lifecycle: "Saved configurations support creator-owned update/delete; published snapshots remain immutable."
    },
    %{
      kind: "revisions",
      collection: "revisions",
      mutable: false,
      lifecycle: "Created by publication; immutable and retained."
    },
    %{
      kind: "executions",
      collection: "executions",
      mutable: false,
      lifecycle: "Created by run; initiator-owned retry/cancel transitions only. History is retained."
    },
    %{
      kind: "attempts",
      collection: "attempts",
      mutable: false,
      lifecycle: "Executor-managed evidence; read-only and retained."
    },
    %{
      kind: "events",
      collection: "events",
      mutable: false,
      lifecycle: "Append-only execution evidence; read-only and retained."
    },
    %{
      kind: "approvals",
      collection: "approvals",
      mutable: false,
      lifecycle: "Created by execution; only the assigned reviewer may decide the persisted payload."
    },
    %{
      kind: "triggers",
      collection: "triggers",
      mutable: true,
      lifecycle:
        "Execution-owner CRUD for schedules and webhooks; use kind-specific collections or the generic trigger collection."
    },
    %{
      kind: "schedules",
      collection: "schedules",
      mutable: true,
      lifecycle: "Execution-owner CRUD; revision, identity and kind cannot be rebound."
    },
    %{
      kind: "webhooks",
      collection: "webhooks",
      mutable: true,
      lifecycle: "Execution-owner CRUD and credential rotation; secrets are returned only on creation/rotation."
    }
  ]

  def primitives, do: @primitives
  def kinds, do: Enum.map(@primitives, & &1.kind)
  def tools(access), do: for({_, ^access, _, _, tool, _} <- @operations, do: tool)

  def access(operation) do
    case Enum.find(@operations, &(elem(&1, 0) == operation)) do
      {_, access, _, _, _, _} -> access
      nil -> nil
    end
  end

  def operations do
    Enum.map(@operations, fn {operation, access, method, path, tool, name} ->
      %{operation: operation, access: access, method: method, path: "/api/automation" <> path, tool: tool, mcp: name}
    end)
  end

  def routes do
    canonical =
      Enum.map(operations(), fn operation ->
        operation |> Map.update!(:path, &String.replace_prefix(&1, "/api", "")) |> Map.put(:parameters, %{})
      end)

    reads =
      for primitive <- @primitives, primitive.kind != "types" do
        %{
          method: :get,
          path: "/automation/#{primitive.collection}",
          operation: :list,
          parameters: %{"kind" => primitive.kind}
        }
      end

    details =
      for kind <- ~w(types behaviors revisions attempts events approvals triggers schedules webhooks) do
        %{method: :get, path: "/automation/#{kind}/:id", operation: :get_record, parameters: %{"kind" => kind}}
      end

    triggers =
      for {collection, kind} <- [{"schedules", "schedule"}, {"webhooks", "webhook"}],
          {method, suffix, operation} <- [
            {:post, "", :trigger},
            {:patch, "/:id", :update_trigger},
            {:delete, "/:id", :delete_trigger},
            {:post, "/:id/enabled", :toggle}
          ] do
        %{
          method: method,
          path: "/automation/#{collection}" <> suffix,
          operation: operation,
          parameters: %{"kind" => kind}
        }
      end

    versions = [
      %{
        method: :get,
        path: "/automation/workflows/:workflow_id/revisions",
        operation: :list,
        parameters: %{"kind" => "revisions"}
      },
      %{method: :post, path: "/automation/workflows/:id/versions", operation: :save, parameters: %{"publish" => true}},
      %{
        method: :get,
        path: "/automation/executions/:run_id/attempts",
        operation: :list,
        parameters: %{"kind" => "attempts"}
      },
      %{
        method: :get,
        path: "/automation/executions/:run_id/events",
        operation: :list,
        parameters: %{"kind" => "events"}
      },
      %{
        method: :post,
        path: "/automation/webhooks/:id/rotate-credential",
        operation: :rotate_trigger,
        parameters: %{"kind" => "webhook"}
      }
    ]

    canonical ++ reads ++ details ++ triggers ++ versions
  end
end
