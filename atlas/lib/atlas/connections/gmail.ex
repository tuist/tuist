defmodule Atlas.Connections.Gmail do
  @moduledoc """
  On-demand Gmail access through the caller's own personal Google connection.
  Reading needs the separate `gmail.readonly` consent and drafts the separate
  `gmail.compose` consent, both granted from `/settings/connections`. Tokens stay
  server-side; results carry message metadata, bounded plain-text bodies and
  attachment listings. `get_attachment/3` returns one attachment's bytes for the
  caller to keep, such as a receipt saved to the document library.

  Sending is never direct: `send_draft/2` sends only a draft whose recipients,
  subject, body and attachments still match a single-use approval its owner
  gave in Atlas.
  """

  alias Atlas.Audit
  alias Atlas.Connections
  alias Atlas.MCP
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

  # Send approvals use the shared MCP tool approval rows under this name.
  @approval_server "gmail"
  @approval_tool "send-draft"

  def scope, do: @read_scope
  def compose_scope, do: @compose_scope
  def approval_server, do: @approval_server

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
      {:ok, %{draft | body: bounded(draft.body)}}
    end
  end

  @doc """
  Creates a plain-text draft. `reply_to_message_id` threads it under that
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
  Sends a draft once its owner approved its current content.

  Returns `{:error, {:approval_required, approval, changed?}}` until then:
  the approval pins a digest of the draft, so `changed?` is true when an
  approval exists for an earlier version of it. Draft updates through Atlas
  wait on the same lock, so they cannot slip in between the check and the send.
  """
  def send_draft(%User{} = user, id) when is_binary(id) do
    with :ok <- valid_id(id) do
      with_locked_draft(user, id, "draft_send", fn token ->
        with {:ok, draft} <- fetch_draft(token, id),
             :ok <- approved(user, id, draft) do
          send_approved(user, token, id, draft)
        end
      end)
    end
  end

  @doc """
  Pending send requests with the draft each one would send, re-read from
  Gmail. `status` is `:ready` while the draft still matches the request,
  `:changed` once it does not and `:unavailable` when Gmail cannot return it.
  """
  def pending_sends(%User{} = user) do
    user
    |> MCP.list_pending_tool_approvals(server_names: [@approval_server])
    |> Enum.map(fn approval ->
      case review(user, approval) do
        {:ok, draft} -> %{approval: approval, draft: draft, status: :ready}
        {:error, {:changed, draft}} -> %{approval: approval, draft: draft, status: :changed}
        {:error, _reason} -> %{approval: approval, draft: nil, status: :unavailable}
      end
    end)
  end

  @doc "Approves a pending send only while the draft still matches it; rejects unconditionally."
  def decide_send(%User{} = user, approval_id, "approved") do
    pending = MCP.list_pending_tool_approvals(user, server_names: [@approval_server])

    with %{} = approval <- Enum.find(pending, &(&1.id == approval_id)) || {:error, :not_found},
         {:ok, _draft} <- review(user, approval) do
      MCP.decide_tool_approval(user, approval.id, "approved", server_names: [@approval_server])
    end
  end

  def decide_send(%User{} = user, approval_id, "rejected"),
    do: MCP.decide_tool_approval(user, approval_id, "rejected", server_names: [@approval_server])

  @doc """
  Saves the owner's edit of a pending send's draft and approves the saved
  content as Gmail then holds it. Agent updates wait on the same draft lock,
  so nothing the owner did not write can be approved in between.
  """
  def revise_send(%User{} = user, approval_id, attrs) when is_map(attrs) do
    pending = MCP.list_pending_tool_approvals(user, server_names: [@approval_server])

    with %{arguments: %{"draft_id" => id}} = approval <-
           Enum.find(pending, &(&1.id == approval_id)) || {:error, :not_found} do
      with_draft_lock(user, id, fn -> save_and_approve(user, approval, id, attrs) end)
    end
  end

  defp save_and_approve(user, approval, id, attrs) do
    with {:ok, _written} <- update_draft(user, id, attrs),
         {:ok, draft} <- with_token(user, [@compose_scope], "draft_review", &fetch_draft(&1, id)) do
      MCP.decide_tool_approval(user, approval.id, "approved",
        server_names: [@approval_server],
        arguments: approval_arguments(id, draft)
      )
    end
  end

  defp review(user, %{arguments: %{"draft_id" => id, "digest" => digest}}) do
    with {:ok, draft} <- with_token(user, [@compose_scope], "draft_review", &fetch_draft(&1, id)) do
      if digest(draft) == digest, do: {:ok, draft}, else: {:error, {:changed, draft}}
    end
  end

  defp review(_user, _approval), do: {:error, :invalid_response}

  defp approved(user, id, draft) do
    case MCP.authorize_tool_call(user, @approval_server, @approval_tool, approval_arguments(id, draft)) do
      {:ok, _approval} ->
        :ok

      {:approval_required, approval} ->
        changed? =
          user
          |> MCP.list_tool_approvals("approved", server_names: [@approval_server])
          |> Enum.any?(&(&1.tool_name == @approval_tool and &1.arguments["draft_id"] == id))

        {:error, {:approval_required, approval, changed?}}
    end
  end

  defp send_approved(user, token, id, draft) do
    case request(:post, "/drafts/send", token, json: %{"id" => id}) do
      {:ok, sent} ->
        audit(user, "connection.gmail_draft_sent", %{
          "draft_id" => id,
          "message_id" => sent["id"],
          "recipient_count" => length(draft.recipients)
        })

        {:ok, %{draft_id: id, message_id: sent["id"], thread_id: sent["threadId"]}}

      # The approval is spent and Gmail may still have sent the message.
      {:error, reason} when reason in [:provider_unavailable, :rate_limited] ->
        {:error, :send_unconfirmed}

      error ->
        error
    end
  end

  # The digest covers what the recipients would receive. Thread and reply
  # headers are left out: they decide where the message files, not what it says.
  defp approval_arguments(id, draft), do: %{"draft_id" => id, "digest" => digest(draft)}

  defp digest(draft) do
    [draft.to, draft.cc, draft.bcc, draft.subject, draft.body, draft.attachments]
    |> JSON.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp with_locked_draft(user, id, operation, fun),
    do: with_draft_lock(user, id, fn -> with_token(user, [@compose_scope], operation, fun) end)

  # Transaction-scoped and reentrant, so a locked caller can run update_draft/3.
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
           attachments: attachments(payload),
           # Saving from Atlas rewrites the draft as plain text, so only drafts
           # that lose nothing that way can be edited there.
           editable:
             header(headers, "Bcc") == "" and attachments(payload) == [] and
               not Enum.any?(flatten(payload), &(&1["mimeType"] == "text/html")),
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
    reply_to = Map.get(attrs, "reply_to_message_id")

    checks = [
      {recipients?(to, 1), "to must list 1 to #{@max_recipients} plain email addresses."},
      {recipients?(cc, 0), "cc must list up to #{@max_recipients} plain email addresses."},
      {single_line?(subject), "subject must be one line of at most 500 characters."},
      {is_binary(body) and String.valid?(body) and byte_size(body) <= @max_draft_body,
       "body must be plain text of at most #{@max_draft_body} bytes."},
      {is_nil(reply_to) or (is_binary(reply_to) and Regex.match?(@id, reply_to)),
       "reply_to_message_id must be a message id returned by search_my_gmail."}
    ]

    case Enum.find(checks, fn {valid?, _message} -> not valid? end) do
      nil -> {:ok, %{to: to, cc: cc, subject: subject, body: body, reply_to_message_id: reply_to}}
      {false, message} -> {:error, {:invalid, message}}
    end
  end

  defp recipients?(list, min) do
    is_list(list) and length(list) in min..@max_recipients and
      Enum.all?(list, &(is_binary(&1) and byte_size(&1) <= 254 and Regex.match?(@address, &1)))
  end

  defp single_line?(value),
    do: is_binary(value) and String.valid?(value) and String.length(value) <= 500 and not (value =~ ~r/[\r\n\x00]/)

  # RFC 5322 text/plain message with UTF-8 base64 content, sent to Gmail as `raw`.
  defp message(fields, reply) do
    headers =
      [
        {"To", Enum.join(fields.to, ", ")},
        fields.cc != [] && {"Cc", Enum.join(fields.cc, ", ")},
        {"Subject", encode_header(fields.subject)},
        reply && reply.in_reply_to && {"In-Reply-To", reply.in_reply_to},
        reply && reply.references != "" && {"References", reply.references},
        {"MIME-Version", "1.0"},
        {"Content-Type", "text/plain; charset=UTF-8"},
        {"Content-Transfer-Encoding", "base64"}
      ]
      |> Enum.filter(& &1)
      |> Enum.map_join(fn {name, value} -> "#{name}: #{value}\r\n" end)

    body = fields.body |> Base.encode64() |> wrap(76)
    raw = Base.url_encode64(headers <> "\r\n" <> body, padding: false)

    if reply && reply.thread_id, do: %{"raw" => raw, "threadId" => reply.thread_id}, else: %{"raw" => raw}
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

  # Draft attachments above stay as they are: their shape feeds the send-approval digest.
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
