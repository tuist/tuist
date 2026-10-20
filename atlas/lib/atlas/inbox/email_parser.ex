defmodule Atlas.Inbox.EmailParser do
  @moduledoc """
  Extracts the account-routing context Atlas needs from raw RFC822 emails.

  Delegates RFC 822 / MIME parsing to the `mail` library (DockYard/elixir-mail),
  which handles header folding, multipart MIME, quoted-printable, base64, and
  attachment body decoding.
  This module owns the business-logic layer on top: participant role assignment,
  role deduplication, envelope fallback, and markdown rendering.

  The library requires CRLF line endings; `parse/2` normalises the input.
  """

  def parse(raw_email, envelope \\ %{}) when is_binary(raw_email) and is_map(envelope) do
    message = safe_parse(raw_email)

    from = to_participants(Mail.get_from(message), "from") |> or_envelope(envelope["from"], "from")
    to = to_participants(Mail.get_to(message), "to") |> or_envelope(envelope["to"], "to")
    cc = to_participants(Mail.get_cc(message), "cc")
    reply_to = to_participants(Mail.get_reply_to(message), "reply_to")

    participants =
      [from, to, cc, reply_to]
      |> List.flatten()
      |> deduplicate_participants()

    text_body = extract_body(message) |> normalize_body()
    attachments = extract_attachments(message)

    # Mail parses the date header into a UTC DateTime; keep the raw string for metadata.
    date_header = raw_date_header(raw_email)
    occurred_at = parse_occurred_at(message, date_header)

    %{
      raw: raw_email,
      headers: message.headers,
      message_id: message_id(message),
      in_reply_to: message_id_header(message.headers["in-reply-to"]),
      references: message_id_headers(message.headers["references"]),
      subject: Mail.get_subject(message),
      date_header: date_header,
      occurred_at: occurred_at,
      from: from,
      to: to,
      cc: cc,
      reply_to: reply_to,
      participants: participants,
      text_body: text_body,
      attachments: attachments,
      markdown: build_markdown(Mail.get_subject(message), date_header, participants, text_body),
      envelope: envelope
    }
  end

  def participant_emails(email) do
    email.participants |> Enum.map(& &1.email) |> Enum.uniq()
  end

  def to_agent_context(email) do
    %{
      subject: email.subject,
      message_id: email.message_id,
      occurred_at: DateTime.to_iso8601(email.occurred_at),
      from: participant_metadata(email.from),
      to: participant_metadata(email.to),
      cc: participant_metadata(email.cc),
      reply_to: participant_metadata(email.reply_to),
      participants: participant_metadata(email.participants),
      attachments: attachment_metadata(Map.get(email, :attachments, [])),
      text_body: truncate(email.text_body, 12_000)
    }
  end

  def participant_metadata(participants) when is_list(participants) do
    Enum.map(participants, &%{"email" => &1.email, "name" => &1.name, "roles" => &1.roles})
  end

  def email_domain(email) when is_binary(email) do
    case String.split(String.downcase(email), "@", parts: 2) do
      [_local, domain] -> domain
      _ -> nil
    end
  end

  def truncate(nil, _max), do: nil

  def truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "\n\n[truncated]", else: text
  end

  def pdf_attachments(email) when is_map(email) do
    email
    |> Map.get(:attachments, [])
    |> Enum.filter(&pdf_attachment?/1)
  end

  @doc """
  Returns an email's HTML representation with inline `cid:` image references
  rewritten through the supplied URL function. Falls back to a safely escaped
  text representation when the message has no HTML part.
  """
  def original_html(raw_email, inline_attachment_url)
      when is_binary(raw_email) and is_function(inline_attachment_url, 1) do
    message = safe_parse(raw_email)

    case extract_html_body(message) do
      html when is_binary(html) and html != "" -> replace_content_ids(html, inline_attachment_url)
      _ -> text_fallback_html(extract_body(message))
    end
  end

  @doc "Returns an inline attachment identified by its Content-ID."
  def inline_attachment(raw_email, content_id) when is_binary(raw_email) and is_binary(content_id) do
    case normalize_content_id(content_id) do
      nil ->
        nil

      normalized_content_id ->
        raw_email
        |> safe_parse()
        |> collect_attachment_parts()
        |> Enum.find_value(fn part ->
          attachment = attachment_from_part(part)

          if attachment && attachment.content_id == normalized_content_id, do: attachment
        end)
    end
  end

  @doc "Returns an attachment identified by its filename."
  def attachment_by_filename(raw_email, filename) when is_binary(raw_email) and is_binary(filename) do
    raw_email
    |> safe_parse()
    |> collect_attachment_parts()
    |> Enum.find_value(fn part ->
      attachment = attachment_from_part(part)
      if attachment && attachment.filename == Path.basename(filename), do: attachment
    end)
  end

  @doc "Returns an attachment identified by its SHA-256 checksum."
  def attachment_by_checksum(raw_email, checksum) when is_binary(raw_email) and is_binary(checksum) do
    raw_email
    |> safe_parse()
    |> collect_attachment_parts()
    |> Enum.find_value(fn part ->
      attachment = attachment_from_part(part)
      if attachment && attachment.checksum_sha256 == checksum, do: attachment
    end)
  end

  def attachment_metadata(attachments) when is_list(attachments) do
    Enum.map(attachments, &attachment_to_metadata/1)
  end

  # -- Address helpers --

  defp to_participants(nil, _role), do: []
  defp to_participants([], _role), do: []
  defp to_participants(list, role) when is_list(list), do: Enum.flat_map(list, &to_participants(&1, role))

  defp to_participants({name, email}, role) when is_binary(email),
    do: [%{email: normalize_email(email), name: normalize_name(name), roles: [role]}]

  defp to_participants(email, role) when is_binary(email),
    do: [%{email: normalize_email(email), name: nil, roles: [role]}]

  defp to_participants(_, _role), do: []

  defp or_envelope([], value, role) when is_binary(value) and value != "" do
    [%{email: normalize_email(value), name: nil, roles: [role]}]
  end

  defp or_envelope(participants, _value, _role), do: participants

  defp deduplicate_participants(participants) do
    participants
    |> Enum.reduce(%{}, fn p, acc ->
      Map.update(acc, p.email, p, fn existing ->
        %{existing | name: existing.name || p.name, roles: Enum.uniq(existing.roles ++ p.roles)}
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.email)
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp normalize_name(nil), do: nil

  defp normalize_name(name) do
    trimmed = name |> String.trim() |> String.trim("\"")
    if trimmed != "", do: trimmed
  end

  # -- Body extraction --

  defp extract_body(%{multipart: true, parts: parts}), do: extract_multipart_body(parts)

  defp extract_body(%{body: body, headers: headers}) do
    if html_content_type?(headers["content-type"]), do: html_to_text(body), else: body
  end

  defp extract_multipart_body(parts) do
    find_part_body(parts, "text/plain") ||
      html_to_text(find_part_body(parts, "text/html"))
  end

  defp extract_html_body(%{multipart: true, parts: parts}), do: find_part_body(parts, "text/html")

  defp extract_html_body(%{body: body, headers: headers}) do
    if html_content_type?(headers["content-type"]), do: body
  end

  defp find_part_body(parts, target_type) do
    Enum.find_value(parts, fn part ->
      ct = part.headers["content-type"]

      cond do
        part.multipart -> find_part_body(part.parts, target_type)
        content_type_matches?(ct, target_type) -> part.body
        true -> nil
      end
    end)
  end

  defp content_type_matches?(nil, "text/plain"), do: true

  defp content_type_matches?([main | _], target) when is_binary(main),
    do: String.starts_with?(String.downcase(main), target)

  defp content_type_matches?(ct, target) when is_binary(ct), do: String.starts_with?(String.downcase(ct), target)
  defp content_type_matches?(_, _), do: false

  defp html_content_type?(nil), do: false
  defp html_content_type?([main | _]) when is_binary(main), do: String.contains?(String.downcase(main), "html")
  defp html_content_type?(ct) when is_binary(ct), do: String.contains?(String.downcase(ct), "html")
  defp html_content_type?(_), do: false

  defp html_to_text(nil), do: nil

  defp html_to_text(html) do
    html
    |> String.replace(~r/<(?:style|script)\b[^>]*>.*?<\/(?:style|script)\s*>/is, "")
    |> String.replace(~r/<\s*br\s*\/?\s*>/i, "\n")
    |> String.replace(~r/<\s*\/p\s*>/i, "\n\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end

  defp normalize_body(nil), do: nil
  defp normalize_body(body), do: body |> String.replace("\r\n", "\n") |> String.replace("\r", "\n") |> String.trim()

  # -- Attachment extraction --

  defp extract_attachments(message) do
    message
    |> collect_attachment_parts()
    |> Enum.map(&attachment_from_part/1)
    |> Enum.reject(&is_nil/1)
  end

  defp collect_attachment_parts(%Mail.Message{} = message) do
    current =
      if attachment_part?(message) do
        [message]
      else
        []
      end

    current ++ Enum.flat_map(message.parts, &collect_attachment_parts/1)
  end

  defp attachment_part?(message) do
    Mail.Message.is_attachment?(message, :all) or is_binary(attachment_content_id(message))
  end

  defp attachment_from_part(%Mail.Message{body: body} = part) when is_binary(body) do
    content_type = attachment_content_type(part)
    filename = attachment_filename(part, content_type)

    %{
      filename: filename,
      content_type: content_type,
      body: body,
      byte_size: byte_size(body),
      checksum_sha256: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower),
      content_id: attachment_content_id(part)
    }
  end

  defp attachment_from_part(_part), do: nil

  defp attachment_content_type(part) do
    part
    |> Mail.Message.get_content_type()
    |> List.first()
    |> case do
      content_type when is_binary(content_type) and content_type != "" -> String.downcase(content_type)
      _ -> "application/octet-stream"
    end
  end

  defp attachment_filename(part, content_type) do
    filename =
      header_param(part.headers["content-disposition"], "filename") ||
        header_param(part.headers["content-type"], "name") ||
        "attachment"

    filename
    |> Path.basename()
    |> ensure_filename(content_type)
  end

  defp attachment_content_id(part) do
    part.headers
    |> Map.get("content-id")
    |> normalize_content_id()
  end

  defp normalize_content_id(content_id) when is_binary(content_id) do
    content_id
    |> String.trim()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_content_id(_content_id), do: nil

  defp attachment_to_metadata(attachment) do
    %{
      "filename" => attachment.filename,
      "content_type" => attachment.content_type,
      "byte_size" => attachment.byte_size,
      "checksum_sha256" => attachment.checksum_sha256
    }
    |> maybe_put_content_id(attachment.content_id)
  end

  defp maybe_put_content_id(metadata, content_id) when is_binary(content_id),
    do: Map.put(metadata, "content_id", content_id)

  defp maybe_put_content_id(metadata, _content_id), do: metadata

  defp header_param(header, key) do
    case List.wrap(header) do
      [_value | params] -> Enum.find_value(params, &matching_header_param(&1, key))
      _ -> nil
    end
  end

  defp matching_header_param({param_key, value}, expected_key) when param_key == expected_key and is_binary(value),
    do: value

  defp matching_header_param(_param, _key), do: nil

  defp ensure_filename("", content_type), do: ensure_filename("attachment", content_type)

  defp ensure_filename(filename, "application/pdf") do
    if filename |> String.downcase() |> String.ends_with?(".pdf") do
      filename
    else
      filename <> ".pdf"
    end
  end

  defp ensure_filename(filename, _content_type), do: filename

  defp replace_content_ids(html, inline_attachment_url) do
    Regex.replace(~r/cid:([^\s"'>]+)/i, html, fn _match, content_id ->
      inline_attachment_url.(normalize_content_id(content_id) || content_id)
    end)
  end

  defp text_fallback_html(body) do
    escaped_body =
      (body || "")
      |> to_string()
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    """
    <!doctype html>
    <html>
      <body>
        <pre>#{escaped_body}</pre>
      </body>
    </html>
    """
  end

  defp pdf_attachment?(%{body: body} = attachment) when is_binary(body) do
    attachment.content_type == "application/pdf" or
      String.ends_with?(String.downcase(attachment.filename), ".pdf") or
      match?(<<"%PDF-", _rest::binary>>, body)
  end

  defp pdf_attachment?(_attachment), do: false

  # -- Header helpers --

  # The mail library crashes on certain malformed header values (e.g. an invalid
  # Date). On failure we strip the Date header and retry so the rest of the email
  # is still parsed correctly; `occurred_at` falls back to `DateTime.utc_now/0`.
  defp safe_parse(raw_email) do
    raw_email |> normalize_crlf() |> Mail.parse()
  rescue
    _ ->
      raw_email
      |> String.replace(~r/(?:^|\r?\n)date:[^\r\n]+/i, "")
      |> normalize_crlf()
      |> Mail.parse()
  end

  defp normalize_crlf(raw), do: String.replace(raw, ~r/\r?\n/, "\r\n")

  defp raw_date_header(raw_email) do
    case Regex.run(~r/(?:^|\r?\n)date:\s*([^\r\n]+)/i, raw_email) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp parse_occurred_at(message, date_header) do
    case message.headers["date"] do
      %DateTime{} = dt -> DateTime.truncate(dt, :second)
      _ -> parse_date_string(date_header) || DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end

  @date_regex ~r/^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s+([+\-]\d{4}|UT|UTC|GMT|Z)/i

  @months %{
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12
  }

  defp parse_date_string(nil), do: nil

  defp parse_date_string(date_header) do
    case Regex.run(@date_regex, String.trim(date_header)) do
      [_match, day, month, year, hour, minute, second, zone] ->
        with {:ok, month_num} <- Map.fetch(@months, String.downcase(month)),
             {:ok, date} <- Date.new(to_int(year), month_num, to_int(day)),
             {:ok, time} <- Time.new(to_int(hour), to_int(minute), to_int(second_or_zero(second))),
             {:ok, naive} <- NaiveDateTime.new(date, time) do
          naive
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.add(-offset_seconds(zone), :second)
          |> DateTime.truncate(:second)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp to_int(value), do: String.to_integer(value)

  defp second_or_zero(nil), do: "0"
  defp second_or_zero(""), do: "0"
  defp second_or_zero(s), do: s

  defp offset_seconds(zone) when zone in ["UT", "UTC", "GMT", "Z"], do: 0

  defp offset_seconds(<<sign, hour::binary-size(2), minute::binary-size(2)>>) do
    if(sign == ?-, do: -1, else: 1) * (String.to_integer(hour) * 3600 + String.to_integer(minute) * 60)
  end

  defp message_id(message) do
    message_id_header(message.headers["message-id"])
  end

  defp message_id_header(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("<")
    |> String.trim_trailing(">")
    |> case do
      "" -> nil
      message_id -> message_id
    end
  end

  defp message_id_header(_value), do: nil

  defp message_id_headers(value) when is_binary(value) do
    Regex.scan(~r/<([^>]+)>|([^\s<>]+)/, value)
    |> Enum.map(fn match -> match |> List.last() |> message_id_header() end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp message_id_headers(values) when is_list(values) do
    values
    |> Enum.flat_map(&message_id_headers/1)
    |> Enum.uniq()
  end

  defp message_id_headers(_value), do: []

  # -- Markdown --

  defp build_markdown(subject, date_header, participants, text_body) do
    [
      "**Subject:** #{subject || "-"}",
      "**Date:** #{date_header || "-"}",
      "**Participants:** #{participant_line(participants)}",
      "",
      "## Email body",
      "",
      truncate(text_body, 16_000) || ""
    ]
    |> Enum.join("\n")
  end

  defp participant_line([]), do: "-"

  defp participant_line(participants) do
    Enum.map_join(participants, ", ", fn
      %{name: nil, email: email} -> email
      %{name: name, email: email} -> "#{name} <#{email}>"
    end)
  end
end
