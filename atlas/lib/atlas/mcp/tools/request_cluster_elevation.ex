defmodule Atlas.MCP.Tools.RequestClusterElevation do
  @moduledoc """
  Grants an Amp orb thread write access to the canary or production cluster,
  once the person the agent works for approves that exact call in Atlas.

  This replaces the Slack `/elevate <env> --thread` round trip for agents. The
  first call files an approval request and returns a link to `/admin/mcps`; the
  person approves it from their browser session; the identical call then asks
  tuist-ops (`Atlas.TuistOps`) to grant the elevation, as that person. tuist-ops
  still requires an engineering tailnet role, and the elevation only counts
  when that person created the thread. Each approval grants once.
  """

  use Atlas.MCP.Tool,
    name: "request_cluster_elevation",
    schema: %{
      "type" => "object",
      "required" => ["env", "thread_id", "intent", "duration_minutes"],
      "properties" => %{
        "env" => %{
          "type" => "string",
          "enum" => ["canary", "production"],
          "description" => "Cluster to write to. Staging is always writable and needs no elevation."
        },
        "thread_id" => %{
          "type" => "string",
          "pattern" => "^T-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
          "description" => "The Amp thread to elevate (`$AMP_CURRENT_THREAD_ID`). Only the person's own threads count."
        },
        "intent" => %{
          "type" => "string",
          "minLength" => 5,
          "maxLength" => 500,
          "description" => "Exactly what the elevation is for. The person approves this text; stay within it."
        },
        "duration_minutes" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 60,
          "description" => "How long the write access lasts, at most 60 minutes."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["env", "thread_id", "expires_at"],
      "properties" => %{
        "env" => %{"type" => "string"},
        "thread_id" => %{"type" => "string"},
        "expires_at" => %{"type" => "string"}
      },
      "additionalProperties" => false
    }

  alias Atlas.MCP, as: MCPContext
  alias Atlas.MCP.Tool
  alias Atlas.TuistOps
  alias Atlas.Users.User

  # Recorded under this name at /admin/mcps and in the approval audit events.
  @server "tuist-ops"
  @approval_tool "request-cluster-elevation"

  @impl EMCP.Tool
  def description do
    "[tuist-ops] Give an Amp orb thread write access to the canary or production Kubernetes cluster for a bounded " <>
      "time. Each elevation needs the approval of the person you work for: the first call files a request and " <>
      "returns a link, the person approves it in Atlas, and the same call with identical arguments then grants it " <>
      "once. Never approve it yourself. Do only what the intent says."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_authenticated(conn, "Cluster elevations"),
         :ok <- validate(args),
         :ok <- TuistOps.configured(),
         {:ok, %User{} = user, approval} <- approve(conn, args),
         {:ok, body} <-
           TuistOps.grant_thread_elevation(user.email, %{
             "env" => args["env"],
             "thread_id" => args["thread_id"],
             "intent" => args["intent"],
             "ttl_seconds" => args["duration_minutes"] * 60,
             "approval_id" => approval.id
           }) do
      {:ok, %{env: body["env"], thread_id: body["thread_id"], expires_at: body["expires_at"]}}
    end
  end

  defp validate(args) do
    case ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(input_schema()), args) do
      :ok -> :ok
      {:error, _errors} -> {:error, "Arguments do not match the #{name()} schema."}
    end
  end

  # Only a person calling over their own MCP connection can spend an approval;
  # the Slack agent acts as a fixed operator and never reaches a grant.
  defp approve(%{assigns: %{current_user: %User{} = user, audit_interface: "mcp"}}, args) do
    case MCPContext.authorize_tool_call(user, @server, @approval_tool, args) do
      {:ok, approval} ->
        {:ok, user, approval}

      {:approval_required, approval} ->
        {:error,
         "Elevating #{args["thread_id"]} on #{args["env"]} needs a person's approval for this exact call. " <>
           "Ask the person you are working for to approve request #{approval.id} at " <>
           "#{AtlasWeb.Endpoint.url()}/admin/mcps#mcp-approval-#{approval.id} " <>
           "(it expires at #{DateTime.to_iso8601(approval.expires_at)}), then repeat the call with identical arguments. " <>
           "Never approve it yourself."}
    end
  end

  defp approve(_conn, _args),
    do: {:error, "Cluster elevations need a person's approval and are only callable over Atlas MCP."}
end
