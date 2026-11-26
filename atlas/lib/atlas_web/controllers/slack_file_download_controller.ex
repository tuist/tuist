defmodule AtlasWeb.SlackFileDownloadController do
  @moduledoc """
  Serves one Slack file to whoever presents a valid short-lived signed token
  from `download_my_slack_file`. The token is the auth, like contract template
  links, because the MCP client that saves the file has no Atlas session. The
  file is fetched from Slack with the signing user's own token on each request
  and never stored.
  """

  use AtlasWeb, :controller

  alias Atlas.Audit
  alias Atlas.Connections.Slack
  alias Atlas.Users
  alias Atlas.Users.User

  def show(conn, %{"file_id" => file_id, "token" => token}) when is_binary(token) do
    with {:ok, %{"user_id" => user_id, "file_id" => ^file_id} = claims} <- Slack.verify_download_token(token),
         %User{} = user <- Users.get_user(user_id),
         {:ok, file} <- download(user, file_id, claims) do
      conn
      |> put_resp_content_type(file.mimetype || "application/octet-stream", nil)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename(file)}"))
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, file.body)
    else
      {:error, :expired} ->
        send_resp(conn, 410, "This download link has expired. Call download_my_slack_file again.")

      {:error, {:invalid, message}} ->
        send_resp(conn, 422, message)

      {:error, reason} when reason in [:needs_authorization, :not_connected, :insufficient_scope] ->
        send_resp(conn, 403, "The Slack connection cannot read this file. Reconnect Slack in Atlas settings.")

      {:error, :rate_limited} ->
        send_resp(conn, 429, "Slack is rate limiting requests. Try again shortly.")

      {:error, :provider_unavailable} ->
        send_resp(conn, 502, "Slack is unavailable. Try again shortly.")

      _other ->
        send_resp(conn, 404, "Not Found")
    end
  end

  def show(conn, _params), do: send_resp(conn, 404, "Not Found")

  # Record the read against the MCP call that minted the link, not as a
  # system action. Links minted before the claims were signed in carry none.
  defp download(user, file_id, claims) do
    context = %{actor: user, interface: claims["interface"] || "system", metadata: claims["metadata"] || %{}}
    Audit.with_context(context, fn -> Slack.download_file(user, file_id) end)
  end

  defp filename(file) do
    (file.name || file.id || "slack-file") |> String.replace(~r/[^\w.\- ]+/u, "_")
  end
end
