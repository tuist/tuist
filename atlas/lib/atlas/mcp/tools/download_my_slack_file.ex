defmodule Atlas.MCP.Tools.DownloadMySlackFile do
  @moduledoc """
  Returns a short-lived link to one Slack file the caller can see. The link is
  served by Atlas, which fetches the file from Slack with the caller's own token
  when the link is opened and does not store it.
  """

  use Atlas.MCP.Tool,
    name: "download_my_slack_file",
    schema: %{
      "type" => "object",
      "required" => ["file_id"],
      "properties" => %{
        "file_id" => %{
          "type" => "string",
          "pattern" => "^F[A-Z0-9]+$",
          "description" => "A file id listed by search_my_slack or read_my_slack_conversation, such as F0123ABCD."
        }
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["file", "download_url", "expires_at"],
      "properties" => %{
        "file" => Atlas.Connections.Slack.file_schema(),
        "download_url" => %{"type" => "string"},
        "expires_at" => %{"type" => "string"}
      },
      "additionalProperties" => false
    }

  alias Atlas.Audit
  alias Atlas.Connections.Slack
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ManageAccountConnections
  alias Atlas.MCP.Tools.ReadMySlackConversation

  @impl EMCP.Tool
  def description do
    "Get a download link for one Slack file the caller can see, through their personal Slack connection (not the Atlas bot). " <>
      "Fetch download_url with an HTTP GET (for example `curl -o <name> <download_url>`) before expires_at, five minutes " <>
      "from now; anyone holding the link can download the file until then, so do not share it. Files up to " <>
      "#{div(Slack.max_file_bytes(), 1024 * 1024)} MB; links to Google Drive and other external storage are refused."
  end

  def execute(conn, %{"file_id" => file_id}) when is_binary(file_id) do
    with true <- ManageAccountConnections.allowed_context?(conn) || {:error, :shared_identity},
         :ok <- Tool.authorize_authenticated(conn, "Slack tools"),
         true <-
           String.match?(file_id, ~r/^F[A-Z0-9]+$/) || {:error, "file_id must be a Slack file id such as F0123ABCD."},
         user = Tool.current_user(conn),
         {:ok, file} <- Slack.file_info(user, file_id) do
      expires_at = DateTime.utc_now() |> DateTime.add(Slack.download_max_age(), :second) |> DateTime.truncate(:second)

      {:ok,
       %{
         file: file,
         download_url: Slack.download_url(user, file_id, Audit.context_from_conn(conn)),
         expires_at: DateTime.to_iso8601(expires_at)
       }}
    else
      {:error, :shared_identity} -> {:error, "Personal Slack reads are unavailable to shared Slack identities."}
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, reason} -> {:error, ReadMySlackConversation.slack_error(reason)}
    end
  end

  def execute(_conn, _args), do: {:error, "file_id is required."}
end
