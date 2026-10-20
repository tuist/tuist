defmodule Atlas.MCP.Tools.ReplyToSupportThread do
  use Atlas.MCP.Tool,
    name: "reply_to_support_thread",
    schema: %{
      "type" => "object",
      "required" => ["thread_id", "body"],
      "properties" => %{
        "thread_id" => %{"type" => "string"},
        "body" => %{
          "type" => "string",
          "description" =>
            "Customer reply to queue for delivery. Interpreted as Markdown: it is rendered to sanitized HTML for the email body and to a plain-text alternative for clients that cannot show HTML, so headings, bold, links, and lists all work. Write it as Markdown, not HTML."
        },
        "reply_all" => %{"type" => "boolean"},
        "attachments" => %{
          "type" => "array",
          "maxItems" => 5,
          "description" =>
            "Optional files to send with the reply. Each file can be at most 5 megabytes; all files together can be at most 15 megabytes.",
          "items" => %{
            "type" => "object",
            "required" => ["filename", "content_base64"],
            "properties" => %{
              "filename" => %{"type" => "string"},
              "content_type" => %{"type" => "string"},
              "content_base64" => %{
                "type" => "string",
                "description" => "File bytes encoded using Base64."
              }
            }
          }
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "thread" => Atlas.MCP.Serializers.Support.thread_schema(),
        "message" => Atlas.MCP.Serializers.Support.message_schema()
      },
      "required" => ["thread", "message"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Support, as: SupportSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Support

  @impl EMCP.Tool
  def description,
    do:
      "Queue a reply to a customer support conversation through contact@tuist.dev. The body is written in Markdown and delivered as sanitized HTML (with a plain-text fallback)."

  def execute(conn, %{"thread_id" => id} = args) do
    with :ok <- Tool.authorize_scope(conn, "support:write", "Support tools"),
         {:ok, reply_attrs} <- reply_attrs(args) do
      case Support.reply(id, reply_attrs, Tool.current_user(conn)) do
        {:ok, %{thread: thread, message: message}} ->
          {:ok, %{thread: SupportSerializer.thread(thread), message: SupportSerializer.message(message)}}

        {:error, :not_found} ->
          {:error, "Support conversation not found: #{id}"}

        {:error, :body_required} ->
          {:error, "body is required."}

        {:error, reason} ->
          {:error, "Could not queue support reply: #{inspect(reason)}"}
      end
    end
  end

  def execute(_conn, _args), do: {:error, "thread_id and body are required."}

  defp reply_attrs(args) do
    with {:ok, attachments} <- decode_attachments(Map.get(args, "attachments", [])) do
      {:ok,
       args
       |> Map.take(["body", "reply_all"])
       |> Map.put("attachments", attachments)}
    end
  end

  defp decode_attachments(attachments) when is_list(attachments) do
    attachments
    |> Enum.reduce_while({:ok, []}, fn attachment, {:ok, decoded} ->
      case decode_attachment(attachment) do
        {:ok, attachment} -> {:cont, {:ok, [attachment | decoded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp decode_attachments(_attachments), do: {:error, "attachments must be a list."}

  defp decode_attachment(%{"filename" => filename, "content_base64" => encoded} = attachment)
       when is_binary(filename) and is_binary(encoded) do
    case Base.decode64(encoded, ignore: :whitespace) do
      {:ok, body} ->
        content_type =
          case Map.get(attachment, "content_type") do
            content_type when is_binary(content_type) and content_type != "" -> content_type
            _content_type -> MIME.from_path(filename)
          end

        {:ok,
         %{
           filename: filename,
           content_type: content_type,
           body: body
         }}

      :error ->
        {:error, "attachments must contain valid Base64 file data."}
    end
  end

  defp decode_attachment(_attachment), do: {:error, "attachments require filename and content_base64."}
end
