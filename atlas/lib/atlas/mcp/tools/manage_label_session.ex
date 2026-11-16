defmodule Atlas.MCP.Tools.ManageLabelSession do
  @moduledoc false
  use Atlas.MCP.Tool,
    name: "manage_label_session",
    schema: %{
      "type" => "object",
      "required" => ["action"],
      "additionalProperties" => false,
      "properties" => %{
        "action" => %{"type" => "string", "enum" => ~w(create status submit preview print cut)},
        "session_id" => %{"type" => "string", "format" => "uuid"},
        "job_id" => %{"type" => "string", "format" => "uuid"},
        "job_ids" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 100,
          "uniqueItems" => true,
          "items" => %{"type" => "string", "format" => "uuid"}
        },
        "cut" => %{"type" => "boolean"},
        "approval" => %{"type" => "boolean"},
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
    "Prepare private Brady M211 labels in Atlas and print them through the owner's Chrome relay. Create returns a private relay URL the owner opens in Chrome beside the printer to connect it. Submit renders previews (base64 PNG and sizing via preview). Print queues a batch of preview-only labels (job_ids in print order, default all) for the connected printer: one label at a time, cut after each label unless cut is false. Cut sends one standalone cut. Output starts directly for at most 20 labels per batch, and only when no other batch in the session is still queued or printing; pass approval: true for owner review first, which a larger batch requires. Inspect sizing: bitmap aspect ratio sets continuous length, preview width_mm/height_mm do not guarantee physical size, and feed/trailer adds tape. Measure one test label before a batch. Only the owner can approve in the browser, never this tool. Read status for per-label printResult/cutResult. Uncertain output stops all queued output and is never retried automatically; inspect the printer, then submit a label again to reprint it."
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
          "print" => :print,
          "cut" => :cut
        }[args["action"]]

      data =
        Map.new([
          {"items", args["items"]},
          {"jobId", args["job_id"]},
          {"jobIds", args["job_ids"]},
          {"cut", args["cut"]},
          {"approval", args["approval"]},
          {"widthMm", args["width_mm"] || 50},
          {"heightMm", args["height_mm"] || 12}
        ])

      result =
        if args["action"] == "create",
          do: Labels.create(user, Tool.audit_interface(conn)),
          else: Labels.request(user, operation, args["session_id"], data, Tool.audit_interface(conn))

      case result do
        {:ok, png} when is_binary(png) ->
          case Labels.request(user, :status, args["session_id"], %{}, Tool.audit_interface(conn)) do
            {:ok, state} ->
              job = Enum.find(state["jobs"], &(&1["id"] == args["job_id"]))
              {:ok, %{result: %{png: Base.encode64(png), content_type: "image/png", sizing: job["sizing"]}}}

            {:error, _, message} ->
              {:error, message}
          end

        {:ok, value} ->
          {:ok, %{result: value}}

        {:error, _, message} ->
          {:error, message}
      end
    else
      _ -> {:error, "Labels require a personal Atlas connection, hardware permission and valid arguments."}
    end
  end
end
