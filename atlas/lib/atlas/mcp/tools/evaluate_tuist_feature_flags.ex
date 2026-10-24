defmodule Atlas.MCP.Tools.EvaluateTuistFeatureFlags do
  @moduledoc "Evaluates Tuist's applicable feature helpers for one account or project."

  use Atlas.MCP.Tool,
    name: "evaluate_tuist_feature_flags",
    schema: Atlas.TuistFeatureFlags.evaluation_schema(),
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "environment" => %{"type" => "string"},
        "resource" => %{
          "type" => "object",
          "properties" => %{
            "account_id" => %{"type" => "integer"},
            "project_id" => %{"type" => ["integer", "null"]}
          },
          "required" => ~w(account_id project_id),
          "additionalProperties" => false
        },
        "evaluations" => %{
          "type" => "array",
          "maxItems" => 17,
          "items" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "feature" => %{"type" => "string"},
              "description" => %{"type" => "string"},
              "actor_type" => %{"type" => "string", "enum" => ~w(global account project)},
              "actor_id" => %{"type" => ["integer", "null"]},
              "enabled" => %{"type" => "boolean"}
            },
            "required" => ~w(name feature description actor_type actor_id enabled),
            "additionalProperties" => false
          }
        }
      },
      "required" => ~w(environment resource evaluations),
      "additionalProperties" => false
    }

  alias Atlas.MCP.Tool
  alias Atlas.TuistFeatureFlags

  @impl EMCP.Tool
  def description do
    "Evaluate feature flags for exactly one positive Tuist account_id OR project_id, not an Atlas UUID. Requires feature_flags:read. " <>
      "A project includes its owning account's flags plus project and global flags; an account does not enumerate its projects. " <>
      "Uses current persisted rules, deterministic percentage enrollment and the serving server's actual feature helpers, " <>
      "including environment defaults, kill switches and dependencies. name identifies the source flag; enabled applies to feature, " <>
      "which differs for inverted kill-switch helpers. Direct pause/kill gates retain their original polarity. Read description. " <>
      "This is a read-only point-in-time evaluation, not proof of past exposure, runtime activation, or every replica's cached decision. " <>
      "Use list/get_tuist_feature_flag to inspect rules and revisions before mutations."
  end

  def execute(conn, args) do
    TuistFeatureFlags.evaluate(Tool.current_user(conn), args, interface: Tool.audit_interface(conn))
  end
end
