defmodule Atlas.MCP.Tools.RequestSpecReview do
  @moduledoc "Records a review request on a spec."

  use Atlas.MCP.Tool,
    name: "request_spec_review",
    schema: %{
      "type" => "object",
      "required" => ["id", "expected_revision"],
      "properties" => %{
        "id" => %{
          "type" => "string",
          "description" => "Spec identifier, public number, or /engineering/specs/:number URL."
        },
        "expected_revision" => %{
          "type" => "integer",
          "description" => "The latest spec revision observed by the caller."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "ok" => %{"type" => "boolean"},
        "spec" => Atlas.MCP.Tools.SpecSerializers.spec_schema()
      },
      "required" => ["ok", "spec"],
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Specs
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.SpecSerializers

  @impl EMCP.Tool
  def description do
    "Record a review request on a spec. Atlas does not have Slack or email notifications wired for specs yet, so the audit event is recorded but no notification is sent."
  end

  def execute(conn, %{"id" => id, "expected_revision" => expected_revision}) do
    user = Tool.current_user(conn)

    case Specs.fetch_visible_spec_by_reference(id, user) do
      {:ok, %{lock_version: ^expected_revision} = spec} ->
        request(spec, user)

      {:ok, spec} ->
        {:error, "Spec revision is stale. Current revision is #{spec.lock_version}."}

      {:error, :not_found} ->
        {:error, "Spec not found."}
    end
  end

  defp request(spec, user) do
    case Specs.request_review(spec, user) do
      {:error, :notifications_not_configured} ->
        {:ok, %{"ok" => true, "spec" => SpecSerializers.spec(Specs.get_spec!(spec.id))}}

      {:error, :unauthorized} ->
        {:error, "Only authenticated operators can request spec reviews."}
    end
  end
end
