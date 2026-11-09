defmodule Atlas.MCP.Tools.ManageLabelSession do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "manage_label_session",
    schema: %{
      "type" => "object",
      "required" => ["action"],
      "additionalProperties" => false,
      "properties" => %{
        "action" => %{"type" => "string", "enum" => ~w(create status submit preview request_print request_cut)},
        "session_id" => %{"type" => "string", "format" => "uuid"},
        "job_id" => %{"type" => "string", "format" => "uuid"},
        "items" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 50,
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "properties" => %{
              "text" => %{"type" => "string", "maxLength" => 120},
              "png" => %{"type" => "string", "maxLength" => 3_000_000}
            }
          }
        },
        "width_mm" => %{"type" => "number", "minimum" => 10, "maximum" => 200},
        "height_mm" => %{"type" => "number", "minimum" => 5, "maximum" => 20}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"result" => %{"type" => "object"}},
      "required" => ["result"],
      "additionalProperties" => false
    }

  alias Atlas.Labels
  alias Atlas.MCP.Tool

  def description do
    "Prepare private Brady M211 labels in Atlas, inspect previews/status and request one print or separate cut. Create returns a private Chrome relay URL. The owner must connect Chrome beside the printer and explicitly approve the exact operation in Atlas. No action here can approve or automatically retry physical output. Preview returns base64 PNG bytes."
  end

  def allowed_context?(%{assigns: assigns} = conn) do
    Tool.audit_interface(conn) in ~w(api mcp) and
      !Map.has_key?(assigns[:mcp_claims] || %{}, "slack_agent") and
      Atlas.Users.has_scope?(Tool.current_user(conn), "assets:read")
  end

  def allowed_context?(_), do: false

  def execute(conn, args) do
    with true <- allowed_context?(conn),
         :ok <- ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(input_schema()), args) do
      user = Tool.current_user(conn)

      operation =
        %{
          "status" => :status,
          "submit" => :submit,
          "preview" => :image,
          "request_print" => :print,
          "request_cut" => :cut
        }[args["action"]]

      data =
        Map.new([
          {"items", args["items"]},
          {"jobId", args["job_id"]},
          {"widthMm", args["width_mm"] || 50},
          {"heightMm", args["height_mm"] || 12}
        ])

      result =
        if args["action"] == "create",
          do: Labels.create(user, Tool.audit_interface(conn)),
          else: Labels.request(user, operation, args["session_id"], data, Tool.audit_interface(conn))

      case result do
        {:ok, png} when is_binary(png) -> {:ok, %{result: %{png: Base.encode64(png), content_type: "image/png"}}}
        {:ok, value} -> {:ok, %{result: value}}
        {:error, _, message} -> {:error, message}
      end
    else
      _ -> {:error, "Labels require a personal Atlas connection, hardware permission and valid arguments."}
    end
  end
end
