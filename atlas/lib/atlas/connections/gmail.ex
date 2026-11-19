defmodule Atlas.Connections.Gmail do
  @moduledoc """
  On-demand Gmail access through the caller's own personal Google connection.
  Reading needs the separate `gmail.readonly` consent and drafts the separate
  `gmail.compose` consent, both granted from `/settings/connections`. Tokens stay
  server-side; results carry message metadata, bounded plain-text bodies and
  attachment listings. `get_attachment/3` returns one attachment's bytes for the
  caller to keep, such as a receipt saved to the document library.

  `send_draft/2` sends immediately. The calling client owns confirmation;
  Atlas does not create send approvals or store draft content.
  """

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.Repo
  alias Atlas.Users.User

  @read_scope "https://www.googleapis.com/auth/gmail.readonly"
  @compose_scope "https://www.googleapis.com/auth/gmail.compose"
  @api "https://gmail.googleapis.com/gmail/v1/users/me"
  @max_results 25
  @max_body 20_000
  # Matches the document library's upload cap.
  @max_attachment_bytes 50 * 1024 * 1024
  @max_draft_body 100_000
  @max_recipients 50
  @id ~r/\A[A-Za-z0-9_-]{1,100}\z/
  # Plain addresses only, so no recipient can carry a display name, header
  # separator or line break into the message.
  @address ~r/\A[A-Za-z0-9.!#$%&'*+\/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+\z/

  def scope, do: @read_scope
  def compose_scope, do: @compose_scope

  def search(%User{} = user, query, limit \\ 10) when is_binary(query) do
    limit = limit |> max(1) |> min(@max_results)

    with_token(user, [@read_scope], "search", fn token ->
      with {:ok, body} <- request(:get, "/messages", token, params: [q: query, maxResults: limit]),
           ids when is_list(ids) <- body |> Map.get("messages", []) |> Enum.map(& &1["id"]),
           {:ok, messages} <- fetch_all(ids, token) do
        audit(user, "connection.gmail_searched", %{"count" => length(messages)})
        {:ok, messages}
      else
        {:error, _} = error -> error
        _ -> {:error, :invalid_response}
      end
    end)
  end

  def get_message(%User{} = user, id) when is_binary(id) do
    with :ok <- valid_id(id) do
      with_token(user, [@read_scope], "message_read", fn token ->
        with {:ok, message} <- request(:get, "/messages/" <> id, token, params: [format: "full"]) do
          audit(user, "connection.gmail_message_read", %{"message_id" => id})
          payload = Map.get(message, "payload", %{})

          {:ok,
           message
           |> summary()
           |> Map.put(:body, payload |> body() |> bounded())
           |> Map.put(:attachments, message_attachments(payload))}
        end
      end)
    end
  end

  @doc """
  Downloads one attachment of a message by the `part_id` that `get_message/2`
  lists. Gmail issues a new attachment id on every read, so the MIME part id is
  the stable reference and the attachment id is looked up again here.
  """
  def get_attachment(%User{} = user, message_id, part_id) when is_binary(message_id) and is_binary(part_id) do
    with :ok <- valid_id(message_id),
         :ok <- valid_part_id(part_id) do
      with_token(user, [@read_scope], "attachment_read", fn token ->
        with {:ok, message} <- request(:get, "/messages/" <> message_id, token, params: [format: "full"]),
             {:ok, part} <- attachment_part(message, part_id),
             {:ok, data} <- attachment_data(token, message_id, part) do
          audit(user, "connection.gmail_attachment_read", %{
            "message_id" => message_id,
            "part_id" => part_id,
            "byte_size" => byte_size(data)
          })

          {:ok, %{filename: part["filename"], mime_type: part["mimeType"], body: data}}
        end
      end)
    end
  end

  def get_draft(%User{} = user, id) when is_binary(id) do
    with :ok <- valid_id(id),
         {:ok, draft} <- with_token(user, [@compose_scope, @read_scope], "draft_read", &fetch_draft(&1, id)) do
      audit(user, "connection.gmail_draft_read", %{"draft_id" => id})
      {:ok, %{draft | body: bounded(draft.body), body_html: bounded(draft.body_html)}}
    end
  end

  @doc """
  Creates a plain-text, Markdown or HTML draft. `reply_to_message_id` threads it under that
  message, which also needs the Gmail read consent to look up its headers.
  """
  def create_draft(%User{} = user, attrs) when is_map(attrs) do
    with {:ok, fields} <- draft_fields(attrs) do
      with_token(user, [@compose_scope], "draft_create", fn token ->
        with {:ok, reply} <- reply(token, fields.reply_to_message_id),
             {:ok, created} <- request(:post, "/drafts", token, json: %{"message" => message(fields, reply)}) do
          audit(user, "connection.gmail_draft_created", %{"draft_id" => created["id"], "reply" => reply != nil})
          {:ok, written(created, fields, reply)}
        end
      end)
    end
  end

  @doc """
  Replaces a draft's recipients, subject and body. Without `reply_to_message_id`
  the draft keeps the thread and reply headers it already has.
  """
  def update_draft(%User{} = user, id, attrs) when is_binary(id) and is_map(attrs) do
    with :ok <- valid_id(id),
         {:ok, fields} <- draft_fields(attrs) do
      with_locked_draft(user, id, "draft_update", fn token ->
        with {:ok, reply} <- update_reply(token, id, fields.reply_to_message_id),
             {:ok, updated} <-
               request(:put, "/drafts/" <> id, token, json: %{"id" => id, "message" => message(fields, reply)}) do
          audit(user, "connection.gmail_draft_updated", %{"draft_id" => id})
          {:ok, written(updated, fields, reply)}
        end
      end)
    end
  end

  @doc """
  Sends the current draft immediately, without an Atlas approval. The calling
  client handles confirmation. Updates and sends serialize on the same lock.
  """
  def send_draft(%User{} = user, id) when is_binary(id) do
    with :ok <- valid_id(id) do
      with_locked_draft(user, id, "draft_send", fn token ->
        with {:ok, draft} <- fetch_draft(token, id) do
          send_current_draft(user, token, id, draft)
        end
      end)
    end
  end

  defp send_current_draft(user, token, id, draft) do
    case request(:post, "/drafts/send", token, json: %{"id" => id}) do
      {:ok, sent} ->
        audit(user, "connection.gmail_draft_sent", %{
          "draft_id" => id,
          "message_id" => sent["id"],
          "recipient_count" => length(draft.recipients)
        })

        {:ok, %{draft_id: id, message_id: sent["id"], thread_id: sent["threadId"]}}

      # Gmail may have sent the message despite an ambiguous transport failure.
      {:error, reason} when reason in [:provider_unavailable, :rate_limited] ->
        {:error, :send_unconfirmed}

      error ->
        error
    end
  end

  defp with_locked_draft(user, id, operation, fun),
    do: with_draft_lock(user, id, fn -> with_token(user, [@compose_scope], operation, fun) end)

  # Serialize updates and sends for the same user's draft.
  defp with_draft_lock(user, id, fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["gmail-draft:#{user.id}:#{id}"])
      fun.()
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  # A 401 before the recorded expiry gets one refreshed token and one retry.
  # Any rejection that remains is reported with Google's status and reason,
  # because a 403 (API disabled, Workspace policy) is not an expired grant and
  # reconnecting does not fix it.
  defp with_token(user, scopes, operation, fun) do
    with {:ok, token} <- Connections.access_token(user, "google", scopes) do
      case fun.(token) do
        {:error, {:http, 401, _reason}} ->
          with {:ok, refreshed} <- Connections.refresh_access_token(user, "google", scopes, token) do
            refreshed |> fun.() |> rejected(user, operation)
          end

        result ->
          rejected(result, user, operation)
      end
    end
  end

  defp rejected({:error, {:http, status, reason}}, user, operation) do
    audit(user, "connection.gmail_failed", %{"operation" => operation, "status" => status, "reason" => reason})

    case {status, reason} do
      {403, reason} when reason in ~w(ACCESS_TOKEN_SCOPE_INSUFFICIENT insufficientPermissions) ->
        {:error, :insufficient_scope}

      {403, reason} when reason in ~w(RATE_LIMIT_EXCEEDED rateLimitExceeded userRateLimitExceeded) ->
        {:error, :rate_limited}

      _ ->
        {:error, {:provider_rejected, status, reason}}
    end
  end

  defp rejected(result, _user, _operation), do: result

  defp fetch_all(ids, token) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      with true <- is_binary(id) and Regex.match?(@id, id),
           {:ok, message} <-
             request(:get, "/messages/" <> id, token,
               params: [
                 format: "metadata",
                 metadataHeaders: "From",
                 metadataHeaders: "To",
                 metadataHeaders: "Subject",
                 metadataHeaders: "Date"
               ]
             ) do
        {:cont, {:ok, [summary(message) | acc]}}
      else
        {:error, :not_found} -> {:cont, {:ok, acc}}
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, :invalid_response}}
      end
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  defp fetch_draft(token, id) do
    case request(:get, "/drafts/" <> id, token, params: [format: "full"]) do
      {:ok, %{"message" => %{} = message}} ->
        headers = get_in(message, ["payload", "headers"]) || []
        payload = Map.get(message, "payload", %{})

        {:ok,
         %{
           id: id,
           message_id: message["id"],
           thread_id: message["threadId"],
           to: header(headers, "To"),
           cc: header(headers, "Cc"),
           bcc: header(headers, "Bcc"),
           subject: header(headers, "Subject"),
           in_reply_to: nilable(header(headers, "In-Reply-To")),
           references: header(headers, "References"),
           body: body(payload),
           body_html: html_body(payload),
           attachments: attachments(payload),
           recipients: Enum.flat_map(~w(To Cc Bcc), &(headers |> header(&1) |> split_addresses()))
         }}

      {:ok, _body} ->
        {:error, :invalid_response}

      error ->
        error
    end
  end

  defp written(response, fields, reply) do
    %{
      id: response["id"],
      message_id: get_in(response, ["message", "id"]),
      thread_id: get_in(response, ["message", "threadId"]),
      to: Enum.join(fields.to, ", "),
      cc: Enum.join(fields.cc, ", "),
      bcc: "",
      subject: fields.subject,
      in_reply_to: reply && reply.in_reply_to,
      body: bounded(fields.body),
      body_html: bounded(fields.body_html),
      attachments: []
    }
  end

  defp reply(_token, nil), do: {:ok, nil}

  defp reply(token, message_id) do
    with {:ok, message} <-
           request(:get, "/messages/" <> message_id, token,
             params: [format: "metadata", metadataHeaders: "Message-ID", metadataHeaders: "References"]
           ),
         headers = get_in(message, ["payload", "headers"]) || [],
         original when original != "" <- single_line(header(headers, "Message-ID")) do
      {:ok,
       %{
         thread_id: message["threadId"],
         in_reply_to: original,
         references: String.trim(single_line(header(headers, "References")) <> " " <> original)
       }}
    else
      "" -> {:error, :invalid_response}
      error -> error
    end
  end

  defp update_reply(token, _id, message_id) when is_binary(message_id), do: reply(token, message_id)

  defp update_reply(token, id, nil) do
    with {:ok, draft} <- fetch_draft(token, id) do
      in_reply_to = draft.in_reply_to && single_line(draft.in_reply_to)
      references = single_line(draft.references)
      # RFC 5322: a reply's References ends with the parent's Message-ID.
      references = if references == "" and in_reply_to, do: in_reply_to, else: references

      {:ok, if(draft.thread_id, do: %{thread_id: draft.thread_id, in_reply_to: in_reply_to, references: references})}
    end
  end

  defp draft_fields(attrs) do
    to = Map.get(attrs, "to", [])
    cc = Map.get(attrs, "cc", [])
    subject = Map.get(attrs, "subject", "")
    body = Map.get(attrs, "body", "")
    format = Map.get(attrs, "body_format", "plain")
    reply_to = Map.get(attrs, "reply_to_message_id")

    checks = [
      {recipients?(to, 1), "to must list 1 to #{@max_recipients} plain email addresses."},
      {recipients?(cc, 0), "cc must list up to #{@max_recipients} plain email addresses."},
      {single_line?(subject), "subject must be one line of at most 500 characters."},
      {is_binary(body) and String.valid?(body) and byte_size(body) <= @max_draft_body,
       "body must be UTF-8 text of at most #{@max_draft_body} bytes."},
      {format in ~w(plain markdown html), "body_format must be plain, markdown or html."},
      {is_nil(reply_to) or (is_binary(reply_to) and Regex.match?(@id, reply_to)),
       "reply_to_message_id must be a message id returned by search_my_gmail."}
    ]

    case Enum.find(checks, fn {valid?, _message} -> not valid? end) do
      nil ->
        fields = %{to: to, cc: cc, subject: subject, reply_to_message_id: reply_to}
        {:ok, Map.merge(fields, draft_content(body, format))}

      {false, message} ->
        {:error, {:invalid, message}}
    end
  end

  defp draft_content(body, "plain"), do: %{body: body, body_html: ""}

  defp draft_content(body, "html") do
    text = body |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> html_text() |> String.trim()
    %{body: text, body_html: body}
  end

  defp draft_content(body, "markdown") do
    %{body: body, body_html: MDEx.to_html!(body, extension: [table: true, strikethrough: true, autolink: true])}
  end

  defp html_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &html_text/1)
  defp html_text(text) when is_binary(text), do: text
  defp html_text({:comment, _}), do: ""
  defp html_text({tag, _, _}) when tag in ~w(script style), do: ""
  defp html_text({"br", _, _}), do: "\n"

  defp html_text({"a", attrs, children}) do
    text = html_text(children)

    case List.keyfind(attrs, "href", 0) do
      {"href", href} when href != "" and href != text -> text <> " (" <> href <> ")"
      _ -> text
    end
  end

  defp html_text({tag, _, children}) when tag in ~w(p div li tr h1 h2 h3 h4 h5 h6 blockquote pre),
    do: html_text(children) <> "\n"

  defp html_text({_tag, _attrs, children}), do: html_text(children)

  defp recipients?(list, min) do
    is_list(list) and length(list) in min..@max_recipients and
      Enum.all?(list, &(is_binary(&1) and byte_size(&1) <= 254 and Regex.match?(@address, &1)))
  end

  defp single_line?(value),
    do: is_binary(value) and String.valid?(value) and String.length(value) <= 500 and not (value =~ ~r/[\r\n\x00]/)

  # RFC 5322 message with UTF-8 base64 content, sent to Gmail as `raw`.
  defp message(fields, reply) do
    {content_headers, body} = mime_content(fields)

    headers =
      [
        {"To", Enum.join(fields.to, ", ")},
        fields.cc != [] && {"Cc", Enum.join(fields.cc, ", ")},
        {"Subject", encode_header(fields.subject)},
        reply && reply.in_reply_to && {"In-Reply-To", reply.in_reply_to},
        reply && reply.references != "" && {"References", reply.references},
        {"MIME-Version", "1.0"}
      ]
      |> Kernel.++(content_headers)
      |> Enum.filter(& &1)
      |> Enum.map_join(fn {name, value} -> "#{name}: #{value}\r\n" end)

    raw = Base.url_encode64(headers <> "\r\n" <> body, padding: false)

    if reply && reply.thread_id, do: %{"raw" => raw, "threadId" => reply.thread_id}, else: %{"raw" => raw}
  end

  defp mime_content(%{body: body, body_html: ""}) do
    {[{"Content-Type", "text/plain; charset=UTF-8"}, {"Content-Transfer-Encoding", "base64"}],
     wrap(Base.encode64(body), 76)}
  end

  defp mime_content(fields) do
    boundary = "atlas-" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    body =
      Enum.map_join([{"text/plain", fields.body}, {"text/html", fields.body_html}], fn {type, content} ->
        "--#{boundary}\r\nContent-Type: #{type}; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" <>
          wrap(Base.encode64(content), 76)
      end) <> "--#{boundary}--\r\n"

    {[{"Content-Type", "multipart/alternative; boundary=\"#{boundary}\""}], body}
  end

  defp wrap(text, width) when byte_size(text) > width do
    binary_part(text, 0, width) <> "\r\n" <> wrap(binary_part(text, width, byte_size(text) - width), width)
  end

  defp wrap("", _width), do: ""
  defp wrap(text, _width), do: text <> "\r\n"

  # RFC 2047 encoded words (at most 75 characters each) for non-ASCII subjects.
  defp encode_header(value) do
    if value =~ ~r/\A[\x20-\x7E]*\z/ do
      value
    else
      value
      |> String.codepoints()
      |> Enum.chunk_while(
        "",
        fn char, acc ->
          if byte_size(acc <> char) > 45, do: {:cont, acc, char}, else: {:cont, acc <> char}
        end,
        &{:cont, &1, ""}
      )
      |> Enum.map_join("\r\n ", &("=?UTF-8?B?" <> Base.encode64(&1) <> "?="))
    end
  end

  defp summary(message) do
    headers = get_in(message, ["payload", "headers"]) || []

    %{
      id: message["id"],
      thread_id: message["threadId"],
      from: header(headers, "From"),
      to: header(headers, "To"),
      subject: header(headers, "Subject"),
      date: header(headers, "Date"),
      snippet: message["snippet"] || "",
      labels: message["labelIds"] || []
    }
  end

  # Prefer the plain-text part; fall back to tag-stripped HTML.
  defp html_body(payload) do
    payload |> flatten() |> Enum.find(%{}, &(&1["mimeType"] == "text/html")) |> decode()
  end

  defp body(payload) do
    parts = flatten(payload)

    case Enum.find(parts, &(&1["mimeType"] == "text/plain")) || Enum.find(parts, &(&1["mimeType"] == "text/html")) do
      %{"mimeType" => "text/html"} = part -> part |> decode() |> strip_html()
      %{} = part -> decode(part)
      nil -> ""
    end
  end

  defp attachments(payload) do
    for %{"filename" => name} = part <- flatten(payload), is_binary(name), name != "" do
      %{"filename" => name, "mime_type" => part["mimeType"], "size" => get_in(part, ["body", "size"])}
    end
  end

  defp message_attachments(payload) do
    for %{"filename" => name, "partId" => part_id} = part <- flatten(payload),
        is_binary(name) and name != "" and is_binary(part_id) do
      %{
        "part_id" => part_id,
        "filename" => name,
        "mime_type" => part["mimeType"],
        "size" => get_in(part, ["body", "size"])
      }
    end
  end

  defp attachment_part(message, part_id) do
    part =
      message
      |> Map.get("payload", %{})
      |> flatten()
      |> Enum.find(&(&1["partId"] == part_id and is_binary(&1["filename"]) and &1["filename"] != ""))

    case part do
      nil ->
        {:error, :not_found}

      %{"body" => %{"size" => size}} when is_integer(size) and size > @max_attachment_bytes ->
        {:error, {:invalid, "The attachment is larger than #{div(@max_attachment_bytes, 1024 * 1024)} MB."}}

      part ->
        {:ok, part}
    end
  end

  # Small attachments arrive inline; larger ones need a separate request.
  defp attachment_data(token, message_id, %{"body" => %{"attachmentId" => id}}) when is_binary(id) do
    with true <- Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, id) || {:error, :invalid_response},
         {:ok, %{"data" => data}} when is_binary(data) <-
           request(:get, "/messages/" <> message_id <> "/attachments/" <> id, token, []) do
      decode_bytes(data)
    else
      {:ok, _body} -> {:error, :invalid_response}
      error -> error
    end
  end

  defp attachment_data(_token, _message_id, %{"body" => %{"data" => data}}) when is_binary(data), do: decode_bytes(data)
  defp attachment_data(_token, _message_id, _part), do: {:error, {:invalid, "The attachment is empty."}}

  defp decode_bytes(data) do
    data
    |> String.trim_trailing("=")
    |> Base.url_decode64(padding: false)
    |> case do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_response}
    end
  end

  defp valid_part_id(part_id) do
    if Regex.match?(~r/\A[0-9]{1,4}(\.[0-9]{1,4}){0,9}\z/, part_id), do: :ok, else: {:error, :not_found}
  end

  defp flatten(%{"parts" => parts} = payload) when is_list(parts), do: [payload | Enum.flat_map(parts, &flatten/1)]
  defp flatten(%{} = payload), do: [payload]
  defp flatten(_), do: []

  defp decode(%{"body" => %{"data" => data}}) when is_binary(data) do
    data
    |> String.trim_trailing("=")
    |> Base.url_decode64(padding: false)
    |> case do
      {:ok, text} -> if String.valid?(text), do: text, else: ""
      :error -> ""
    end
  end

  defp decode(_), do: ""

  defp strip_html(html) do
    html
    |> String.replace(~r/<(script|style)[^>]*>.*?<\/\1>/is, " ")
    |> String.replace(~r/<br\s*\/?>|<\/p>|<\/div>/i, "\n")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/[ \t]+/, " ")
  end

  defp bounded(text), do: text |> String.trim() |> String.slice(0, @max_body)

  defp header(headers, name) when is_list(headers) do
    Enum.find_value(headers, "", fn
      %{"name" => key, "value" => value} when is_binary(key) and is_binary(value) ->
        if String.downcase(key) == String.downcase(name), do: value

      _ ->
        nil
    end)
  end

  defp split_addresses(value),
    do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  # Reply headers copied from another message must not carry a line break.
  defp single_line(value), do: value |> String.replace(~r/[\r\n]+/, " ") |> String.trim()

  defp nilable(""), do: nil
  defp nilable(value), do: value

  defp valid_id(id), do: if(Regex.match?(@id, id), do: :ok, else: {:error, :not_found})

  defp request(method, path, token, opts) do
    case Req.request(
           [
             method: method,
             url: @api <> path,
             auth: {:bearer, token},
             retry: false,
             redirect: false,
             receive_timeout: 15_000
           ] ++ opts
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status, body: body}} when status in 400..499 -> {:error, {:http, status, error_reason(body)}}
      _ -> {:error, :provider_unavailable}
    end
  end

  # Google's machine-readable reason (`SERVICE_DISABLED`, `insufficientPermissions`,
  # ...), never its message, which can quote request details.
  defp error_reason(%{"error" => %{} = error}) do
    candidates =
      Enum.map(List.wrap(error["details"]), &(is_map(&1) && &1["reason"])) ++
        Enum.map(List.wrap(error["errors"]), &(is_map(&1) && &1["reason"])) ++ [error["status"]]

    Enum.find(candidates, "unknown", &(is_binary(&1) and Regex.match?(~r/\A[A-Za-z_]{1,64}\z/, &1)))
  end

  defp error_reason(_body), do: "unknown"

  # Never record queries or message content: the audit trail shows that the
  # caller used their own mailbox, not what it contains.
  defp audit(user, action, metadata) do
    Audit.record(
      action,
      %{
        target_type: "user_connection",
        target_label: "google",
        metadata: Map.merge(%{"provider" => "google", "dashboard_path" => "/settings/connections"}, metadata)
      },
      actor: user
    )
  end
end
