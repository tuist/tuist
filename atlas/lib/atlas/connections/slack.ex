defmodule Atlas.Connections.Slack do
  @moduledoc """
  On-demand Slack reads through the caller's own personal Slack user token:
  message search (`search:read`), channel and thread history (`*:history`) and
  file downloads (`files:read`). This is separate from Atlas's workspace bot:
  results are limited to what the connected person can see in Slack, including
  their private channels, DMs and Slack Connect channels.
  """

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Users.User
  alias AtlasWeb.Endpoint

  @api "https://slack.com/api/"
  @max_results 50
  @max_history 200
  @history_scopes ~w(channels:history groups:history im:history mpim:history)
  @max_file_bytes 50 * 1024 * 1024
  @download_salt "slack-file-download"
  @download_max_age 300

  def max_file_bytes, do: @max_file_bytes

  @doc "Output schema of a message's file in the Slack MCP tools."
  def file_schema do
    %{
      "type" => "object",
      "required" => ["id", "name", "title", "mimetype", "filetype", "size"],
      "properties" => %{
        "id" => %{"type" => ["string", "null"]},
        "name" => %{"type" => ["string", "null"]},
        "title" => %{"type" => ["string", "null"]},
        "mimetype" => %{"type" => ["string", "null"]},
        "filetype" => %{"type" => ["string", "null"]},
        "size" => %{"type" => ["integer", "null"]}
      },
      "additionalProperties" => false
    }
  end

  def search(%User{} = user, query, limit \\ 20) when is_binary(query) do
    limit = limit |> max(1) |> min(@max_results)

    with {:ok, token} <- Connections.access_token(user, "slack", ["search:read"]),
         {:ok, %{"messages" => %{"matches" => matches}}} when is_list(matches) <-
           request(token, "search.messages", query: query, count: limit, sort: "timestamp", sort_dir: "desc") do
      messages = Enum.map(matches, &search_message/1)
      audit(user, "connection.slack_searched", %{"count" => length(messages)})
      {:ok, messages}
    else
      {:ok, _} -> {:error, :invalid_response}
      {:error, _} = error -> error
    end
  end

  @doc """
  Reads a conversation's history, newest first as Slack returns it, or a
  thread's replies (parent first) when `opts[:thread_timestamp]` is set.
  Accepts `:limit`, `:cursor`, `:oldest` and `:latest`.
  """
  def history(%User{} = user, channel_id, opts \\ []) when is_binary(channel_id) do
    thread = opts[:thread_timestamp]
    limit = (opts[:limit] || 50) |> max(1) |> min(@max_history)

    params =
      [channel: channel_id, limit: limit, cursor: opts[:cursor], oldest: opts[:oldest], latest: opts[:latest]]
      |> then(&if(thread, do: [{:ts, thread} | &1], else: &1))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    method = if thread, do: "conversations.replies", else: "conversations.history"

    with {:ok, token} <- Connections.access_token(user, "slack", @history_scopes),
         {:ok, %{"messages" => messages} = body} when is_list(messages) <- request(token, method, params) do
      messages = Enum.map(messages, &message/1)
      audit(user, "connection.slack_history_read", %{"count" => length(messages), "thread" => not is_nil(thread)})

      {:ok,
       %{
         channel_id: channel_id,
         thread_timestamp: thread,
         messages: messages,
         next_cursor: next_cursor(body)
       }}
    else
      {:ok, _} -> {:error, :invalid_response}
      {:error, _} = error -> error
    end
  end

  @doc """
  Looks up a file the caller can see. Refuses files Slack does not host
  (Google Drive and other external links) and files over `max_file_bytes/0`.
  """
  def file_info(%User{} = user, file_id) when is_binary(file_id) do
    with {:ok, token} <- Connections.access_token(user, "slack", ["files:read"]),
         {:ok, file} <- fetch_file(token, file_id) do
      {:ok, Map.delete(file, :download_from)}
    end
  end

  @doc "Downloads a file's bytes with the caller's token, after `file_info/2`'s checks."
  def download_file(%User{} = user, file_id) when is_binary(file_id) do
    with {:ok, token} <- Connections.access_token(user, "slack", ["files:read"]),
         {:ok, file} <- fetch_file(token, file_id),
         {:ok, body} <- fetch_bytes(token, file.download_from) do
      audit(user, "connection.slack_file_read", %{"file_id" => file.id, "byte_size" => byte_size(body)})
      {:ok, file |> Map.delete(:download_from) |> Map.put(:body, body)}
    end
  end

  @doc """
  A link that serves the file to whoever presents it for `download_max_age/0`
  seconds, fetched from Slack with `user`'s own token at that moment. Atlas
  does not store the file.
  """
  def download_url(%User{id: user_id}, file_id) do
    token = Phoenix.Token.sign(Endpoint, @download_salt, %{"user_id" => user_id, "file_id" => file_id})

    Endpoint.url() <>
      "/connections/slack/files/#{URI.encode_www_form(file_id)}?" <> URI.encode_query(%{"token" => token})
  end

  def download_max_age, do: @download_max_age

  def verify_download_token(token) when is_binary(token),
    do: Phoenix.Token.verify(Endpoint, @download_salt, token, max_age: @download_max_age)

  @doc """
  Channel and message timestamp of a Slack message link, such as
  `https://acme.slack.com/archives/C123/p1762230000000200?thread_ts=1762229900.000100`.
  A reply's link resolves to its thread's parent timestamp.
  """
  def parse_permalink(permalink) when is_binary(permalink) do
    uri = URI.parse(permalink)

    with true <- is_binary(uri.host) and String.ends_with?(uri.host, "slack.com"),
         ["archives", channel, "p" <> digits] <- String.split(uri.path || "", "/", trim: true),
         true <- String.match?(digits, ~r/^\d{11,}$/) do
      {seconds, micros} = String.split_at(digits, -6)
      thread = URI.decode_query(uri.query || "")["thread_ts"]
      {:ok, channel, thread || "#{seconds}.#{micros}"}
    else
      _ -> {:error, :invalid_permalink}
    end
  end

  defp fetch_file(token, file_id) do
    case request(token, "files.info", file: file_id) do
      {:ok, %{"file" => %{"is_external" => true}}} ->
        {:error, {:invalid, "That file is a link to storage outside Slack; open it from its source instead."}}

      {:ok, %{"file" => %{"size" => size}}} when is_integer(size) and size > @max_file_bytes ->
        {:error, {:invalid, "That file is #{size} bytes; downloads are limited to #{@max_file_bytes} bytes."}}

      {:ok, %{"file" => %{"url_private_download" => url} = file}} when is_binary(url) ->
        with :ok <- slack_file_host(url), do: {:ok, file |> file() |> Map.put(:download_from, url)}

      {:ok, _} ->
        {:error, :invalid_response}

      {:error, _} = error ->
        error
    end
  end

  # The token must only ever go to Slack's own file host.
  defp slack_file_host(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "files.slack.com"} -> :ok
      _ -> {:error, :invalid_response}
    end
  end

  defp fetch_bytes(token, url) do
    case Req.request(
           method: :get,
           url: url,
           auth: {:bearer, token},
           decode_body: false,
           retry: false,
           redirect: false,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) <= @max_file_bytes -> {:ok, body}
      {:ok, %{status: 200}} -> {:error, {:invalid, "That file exceeds the #{@max_file_bytes}-byte download limit."}}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      # Slack answers an unauthorized file request with a redirect to its sign-in page.
      {:ok, %{status: status}} when status in [302, 401, 403] -> {:error, :needs_authorization}
      _ -> {:error, :provider_unavailable}
    end
  end

  defp next_cursor(%{"response_metadata" => %{"next_cursor" => cursor}}) when is_binary(cursor) and cursor != "",
    do: cursor

  defp next_cursor(_body), do: nil

  defp search_message(match) do
    channel = match["channel"] || %{}

    %{
      text: match["text"] || "",
      user: match["username"] || match["user"],
      channel_id: channel["id"],
      channel_name: channel["name"],
      timestamp: match["ts"],
      thread_timestamp: match["thread_ts"],
      permalink: match["permalink"],
      files: files(match)
    }
  end

  defp message(message) do
    %{
      text: message["text"] || "",
      user: message["user"] || message["username"] || message["bot_id"],
      timestamp: message["ts"],
      thread_timestamp: message["thread_ts"],
      reply_count: message["reply_count"],
      files: files(message)
    }
  end

  defp files(%{"files" => files}) when is_list(files), do: Enum.map(files, &file/1)
  defp files(_message), do: []

  # Slack Connect can return only a file's id (`file_access: check_file_info`);
  # files.info then resolves the rest.
  defp file(file) do
    %{
      id: file["id"],
      name: file["name"],
      title: file["title"],
      mimetype: file["mimetype"],
      filetype: file["filetype"],
      size: file["size"]
    }
  end

  defp request(token, method, params) do
    case Req.request(
           method: :get,
           url: @api <> method,
           auth: {:bearer, token},
           params: params,
           retry: false,
           redirect: false,
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: %{"ok" => true} = body}} ->
        {:ok, body}

      {:ok, %{status: 200, body: %{"error" => "ratelimited"}}} ->
        {:error, :rate_limited}

      {:ok, %{status: 200, body: %{"error" => error}}}
      when error in ~w(invalid_auth token_revoked token_expired missing_scope account_inactive not_authed) ->
        {:error, :needs_authorization}

      {:ok, %{status: 200, body: %{"error" => error}}}
      when error in ~w(channel_not_found not_in_channel thread_not_found file_not_found file_deleted) ->
        {:error, :not_found}

      {:ok, %{status: 200, body: %{"error" => "invalid_cursor"}}} ->
        {:error, {:invalid, "The cursor is invalid or expired; read from the start again."}}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      _ ->
        {:error, :provider_unavailable}
    end
  end

  # Never record queries, channel names or message text.
  defp audit(user, action, metadata) do
    Audit.record(
      action,
      %{
        target_type: "user_connection",
        target_label: "slack",
        metadata: Map.merge(%{"provider" => "slack", "dashboard_path" => "/settings/connections"}, metadata)
      },
      actor: user
    )
  end
end
