defmodule Pulse.Alerting.Tools do
  @moduledoc false
  alias Pulse.Alerting.{Evaluator, Principal}
  alias Pulse.Alerting.Importer
  alias Pulse.MCP.Arguments

  @definitions [
    {"validate_alert_import", "Dry-run lossless Grafana import with explicit execution blockers; no writes.",
     "alert:import", ~w(tenant rules), :read},
    {"list_alert_rules", "List authorized alert rules.", "alert:read", ~w(tenant), :read},
    {"get_alert_rule", "Read an alert rule's current configuration.", "alert:read", ~w(tenant id), :read},
    {"create_alert_rule", "Create an audited rule. Grafana definitions must remain disabled.", "alert:rules:write",
     ~w(tenant id rule operation_id reason), :write},
    {"update_alert_rule", "Replace configuration with an audited revision; resets native lifecycle.",
     "alert:rules:write", ~w(tenant id rule expected_revision operation_id reason), :write},
    {"delete_alert_rule", "Publish an audited tombstone and stop evaluation.", "alert:rules:write",
     ~w(tenant id expected_revision operation_id reason), :write},
    {"list_alert_rule_changes", "Page newest-first through a frozen configuration audit chain; cursors are body-only.",
     "alert:audit:read", ~w(tenant id), :read},
    {"get_alert_rule_revision", "Read a committed historical rule revision.", "alert:audit:read",
     ~w(tenant id revision), :read},
    {"restore_alert_rule_revision", "Restore configuration as a new disabled revision, never rewind history.",
     "alert:rules:write", ~w(tenant id revision expected_revision operation_id reason), :write},
    {"get_alert_state", "Read durable native alert instances and evaluation health.", "alert:read", ~w(tenant id),
     :read},
    {"read_alert_events", "Read committed per-rule transitions with an encrypted application cursor.", "alert:read",
     ~w(tenant id), :read},
    {"preview_alert_rule",
     "Preview native rules or disabled imported expressions with explicit tenant-local source bindings; no alert-state writes or notifications.",
     "alert:preview", ~w(tenant id), :read},
    {"evaluate_alert_rule", "Evaluate an enabled native rule and commit its lifecycle or recording publication intent.",
     "alert:evaluate", ~w(tenant id), :evaluate}
  ]
  @properties %{
    "tenant" => %{"type" => "string", "minLength" => 1},
    "id" => %{"type" => "string", "minLength" => 1},
    "rules" => %{"type" => "array", "items" => %{"type" => "object"}},
    "rule" => %{"type" => "object"},
    "expected_revision" => %{"type" => "string", "minLength" => 1},
    "operation_id" => %{"type" => "string", "minLength" => 1},
    "reason" => %{"type" => "string", "minLength" => 1},
    "revision" => %{"type" => "string", "minLength" => 1},
    "revision_cursor" => %{"type" => "string", "minLength" => 1},
    "cursor" => %{"type" => "string", "minLength" => 1},
    "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
  }

  def list do
    Enum.map(@definitions, fn {name, description, _cap, required, mode} ->
      optional = if(mode == :read, do: ~w(cursor limit), else: ~w(expected_revision))

      optional =
        if(name in ["get_alert_rule_revision", "restore_alert_rule_revision"],
          do: ["revision_cursor" | optional],
          else: optional
        )

      properties = Map.take(@properties, Enum.uniq(required ++ optional))

      %{
        "name" => name,
        "description" => description,
        "inputSchema" => %{"type" => "object", "properties" => properties, "required" => required},
        "annotations" => %{
          "readOnlyHint" => mode == :read,
          "destructiveHint" => mode == :write,
          "idempotentHint" => mode != :evaluate,
          "openWorldHint" => mode == :write
        }
      }
    end)
  end

  def known?(name), do: Enum.any?(@definitions, &(elem(&1, 0) == name))

  def call(name, args, context) do
    with %{conn: conn} <- context,
         true <- is_map(args) and is_binary(args["tenant"]),
         {:ok, principal} <- Principal.authenticate(conn, args["tenant"]),
         {_name, _desc, cap, _required, _mode} <- Enum.find(@definitions, &(elem(&1, 0) == name)),
         :ok <- Principal.authorize(principal, cap),
         tool = Enum.find(list(), &(&1["name"] == name)),
         args = Arguments.normalize(args, tool["inputSchema"]),
         :ok <- Arguments.validate(args, tool["inputSchema"]),
         {:ok, result} <- execute(name, principal, args["id"], Map.drop(args, ~w(tenant id))) do
      {:ok, [%{"type" => "text", "text" => Pulse.JSON.encode!(result)}]}
    else
      {:error, {:invalid_arguments, _}} = error -> error
      {:error, {:graph_source, _, _}} -> {:error, :unsupported_graph_source}
      {:error, {:expression_node, _, _}} -> {:error, :unsupported_expression}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _} -> {:error, :alerting_unavailable}
      _ -> {:error, :unauthorized}
    end
  end

  defp execute("validate_alert_import", _actor, _, params) do
    with {:ok, reports} <- Importer.preview(params["rules"]), do: {:ok, %{"rules" => reports}}
  end

  defp execute("list_alert_rules", actor, _, _), do: Pulse.Alerting.list(actor)
  defp execute("get_alert_rule", actor, id, _), do: Pulse.Alerting.get(actor, id)
  defp execute("create_alert_rule", actor, id, params), do: Pulse.Alerting.create(actor, id, params)
  defp execute("update_alert_rule", actor, id, params), do: Pulse.Alerting.update(actor, id, params)
  defp execute("delete_alert_rule", actor, id, params), do: Pulse.Alerting.delete(actor, id, params)
  defp execute("list_alert_rule_changes", actor, id, params), do: Pulse.Alerting.changes(actor, id, params)

  defp execute("get_alert_rule_revision", actor, id, params),
    do: Pulse.Alerting.historical(actor, id, Map.take(params, ["revision", "revision_cursor"]))

  defp execute("restore_alert_rule_revision", actor, id, params), do: Pulse.Alerting.restore(actor, id, params)
  defp execute("get_alert_state", actor, id, _), do: Pulse.Alerting.state(actor, id)
  defp execute("read_alert_events", actor, id, params), do: Pulse.Alerting.events(actor, id, params)
  defp execute("preview_alert_rule", actor, id, _), do: Evaluator.preview(actor, id)
  defp execute("evaluate_alert_rule", actor, id, _), do: Evaluator.evaluate(actor, id)
end
