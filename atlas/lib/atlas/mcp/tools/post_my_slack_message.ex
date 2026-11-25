defmodule Atlas.MCP.Tools.PostMySlackMessage do
  @moduledoc """
  Posts a Slack message, optionally with files, as the caller through their
  personal Slack connection, once they approve that exact call in Atlas.

  These messages go out under the person's own name, often to customers, so
  every post waits for their approval at `/approvals` (`mcp_tool_approvals`,
  recorded under `slack`/`post-message`). Files are resolved before the
  approval is filed, and the approval pins each file's name, size and SHA-256,
  so content behind a URL cannot change between approval and posting. Only a
  person calling over their own MCP connection can spend an approval; the Slack
  agent acts as a fixed operator and never posts as anyone.
  """

  use Atlas.MCP.Tool,
    name: "post_my_slack_message",
    schema: %{
      "type" => "object",
      "required" => ["channel_id"],
      "properties" => %{
        "channel_id" => %{
          "type" => "string",
          "pattern" => "^[CDG][A-Z0-9]+$",
          "description" =>
            "Channel or DM id, such as C0123ABCD or D0123ABCD. Private channels, DMs and Slack Connect conversations work when you are in them."
        },
        "text" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 40_000,
          "description" => "Message text in Slack mrkdwn. Required unless files are attached."
        },
        "thread_timestamp" => %{
          "type" => "string",
          "pattern" => "^[0-9]+\\.[0-9]+$",
          "description" => "Reply in this thread: the parent message's timestamp, such as 1762229900.000100."
        },
        "reply_broadcast" => %{
          "type" => "boolean",
          "description" =>
            "Also send a thread reply to the channel. Needs thread_timestamp; Slack cannot broadcast files."
        },
        "files" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 10,
          "description" =>
            "Files to attach to the message, each from a public HTTPS url (such as an Amp temporary file URL) or content_base64. " <>
              "At most 50 MB in total; base64 content counts against the 8 MB limit of one MCP request, so pass larger files by url.",
          "items" => %{
            "type" => "object",
            "required" => ["filename"],
            "properties" => %{
              "filename" => %{"type" => "string", "minLength" => 1, "maxLength" => 255},
              "title" => %{"type" => "string", "minLength" => 1, "maxLength" => 255},
              "url" => %{"type" => "string", "pattern" => "^https://", "maxLength" => 2048},
              "content_base64" => %{"type" => "string", "minLength" => 1}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["channel_id", "message_timestamp", "thread_timestamp", "files"],
      "properties" => %{
        "channel_id" => %{"type" => "string"},
        "message_timestamp" => %{"type" => ["string", "null"]},
        "thread_timestamp" => %{"type" => ["string", "null"]},
        "files" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["id", "title", "permalink"],
            "properties" => %{
              "id" => %{"type" => ["string", "null"]},
              "title" => %{"type" => ["string", "null"]},
              "permalink" => %{"type" => ["string", "null"]}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    }

  alias Atlas.Connections.Slack
  alias Atlas.MCP, as: MCPContext
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections
  alias Atlas.Moodboard.SafeHTTP
  alias Atlas.Users.User

  # Recorded under these names at /approvals and in the approval audit events.
  @server "slack"
  @approval_tool "post-message"

  @impl EMCP.Tool
  def description do
    "Post a Slack message as the caller through their personal Slack connection (not the Atlas bot), to a channel, DM " <>
      "or Slack Connect conversation they are in, optionally as a thread reply and with files attached. The message " <>
      "goes out under the person's name, so every post needs their approval: the first call files a request and " <>
      "returns a link, the person reviews the exact text and files in Atlas, and the same call with identical " <>
      "arguments then posts once. Never approve it yourself. A failed post needs a new approval; read the " <>
      "conversation with read_my_slack_conversation before retrying, since Slack may have accepted it."
  end

  def execute(conn, args) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Slack tools"),
         {:ok, user} <- caller(conn),
         :ok <- validate(args),
         {:ok, files} <- resolve_files(args["files"] || []),
         :ok <- Slack.ensure_can_post(user, files != []),
         :ok <- approve(user, args, files),
         {:ok, result} <-
           Slack.post_message(user, args["channel_id"], %{
             text: args["text"],
             thread_timestamp: args["thread_timestamp"],
             reply_broadcast: args["reply_broadcast"],
             files: files
           }) do
      {:ok, result}
    else
      {:error, :shared_identity} -> {:error, "Posting to Slack as a person is unavailable to shared Slack identities."}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, slack_error(reason)}
    end
  end

  # Only a person over their own MCP connection can approve and spend a post.
  defp caller(%{assigns: %{current_user: %User{} = user, audit_interface: "mcp"}}), do: {:ok, user}

  defp caller(_conn),
    do: {:error, "Posting to Slack as a person needs their approval and is only callable over Atlas MCP."}

  defp validate(args) do
    cond do
      ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(input_schema()), args) != :ok ->
        {:error, "Arguments do not match the #{name()} schema."}

      args["text"] in [nil, ""] and args["files"] in [nil, []] ->
        {:error, "Pass text, files or both."}

      args["reply_broadcast"] == true and is_nil(args["thread_timestamp"]) ->
        {:error, "reply_broadcast needs thread_timestamp."}

      args["reply_broadcast"] == true and args["files"] not in [nil, []] ->
        {:error, "Slack cannot broadcast a thread reply with files; post the files without reply_broadcast."}

      true ->
        :ok
    end
  end

  defp resolve_files(files) do
    files
    |> Enum.reduce_while({:ok, [], 0}, fn file, {:ok, resolved, total} ->
      with {:ok, body} <- file_body(file),
           total = total + byte_size(body),
           true <- total <= Slack.max_upload_bytes() || {:error, too_large()} do
        {:cont, {:ok, [%{filename: file["filename"], title: file["title"], body: body} | resolved], total}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, resolved, _total} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp file_body(%{"url" => _, "content_base64" => _} = file),
    do: {:error, "Pass either url or content_base64 for #{file["filename"]}, not both."}

  defp file_body(%{"content_base64" => content} = file) do
    case Base.decode64(content, ignore: :whitespace) do
      {:ok, body} when body != "" -> {:ok, body}
      _ -> {:error, "content_base64 for #{file["filename"]} is not valid base64."}
    end
  end

  defp file_body(%{"url" => url} = file) do
    case SafeHTTP.fetch(url, max_bytes: Slack.max_upload_bytes(), timeout: 60_000, media_bodies: true) do
      {:ok, %{status: 200, body: body}} when body != "" ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "Downloading #{file["filename"]} returned HTTP #{status}. Check that the url is current."}

      {:error, _reason} ->
        {:error,
         "Could not download #{file["filename"]}: the url must be a reachable public HTTPS address and the file " <>
           "at most #{div(Slack.max_upload_bytes(), 1024 * 1024)} MB."}
    end
  end

  defp file_body(file), do: {:error, "Pass url or content_base64 for #{file["filename"]}."}

  defp too_large, do: "Attached files exceed #{div(Slack.max_upload_bytes(), 1024 * 1024)} MB in total."

  # The person approves what will be posted: the target, the text and each
  # file's name, size and digest, not the url or base64 it came from.
  defp approve(user, args, files) do
    approval_args =
      args
      |> Map.take(~w(channel_id thread_timestamp reply_broadcast text))
      |> then(fn approval_args ->
        if files == [], do: approval_args, else: Map.put(approval_args, "files", Enum.map(files, &file_summary/1))
      end)

    case MCPContext.authorize_tool_call(user, @server, @approval_tool, approval_args) do
      {:ok, _approval} ->
        :ok

      {:approval_required, approval} ->
        {:error,
         "Posting to Slack as the person you work for needs their approval for this exact message. Ask them to " <>
           "approve request #{approval.id} at #{AtlasWeb.Endpoint.url()}/approvals/#{approval.id} " <>
           "(it expires at #{DateTime.to_iso8601(approval.expires_at)}), then repeat the call with identical arguments " <>
           "and file contents. Never approve it yourself."}
    end
  end

  defp file_summary(file) do
    %{
      "filename" => file.filename,
      "title" => file.title,
      "byte_size" => byte_size(file.body),
      "sha256" => :sha256 |> :crypto.hash(file.body) |> Base.encode16(case: :lower)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp slack_error(:insufficient_scope) do
    "Your Slack connection does not allow posting messages or uploading files yet. Reconnect Slack at " <>
      AtlasWeb.Endpoint.url() <> "/settings/connections to grant it."
  end

  defp slack_error(reason), do: ManageAccountConnections.connection_error("Slack", reason)
end
