defmodule Atlas.Orbit.AttachmentContext do
  @moduledoc """
  Bounded attachment input for Condukt 1.13: UTF-8/PDF excerpts in the prompt
  and base64 image maps in `images:`. No generic file parts are supported by
  that Condukt version. Unsupported or unavailable contents are stated explicitly.
  """

  alias Atlas.Documents.TextExtractor
  alias Atlas.Orbit.Attachments
  alias Atlas.Repo

  @text_budget 48_000
  @text_per_file 12_000
  @image_budget 5 * 1024 * 1024
  @image_count 4
  @text_types ~w(application/json application/xml application/csv)
  @image_types ~w(image/png image/jpeg image/gif image/webp)

  def build(messages, user) do
    state = %{contexts: %{}, images: [], image_bytes: 0, text_bytes: 0}

    state =
      messages
      |> Repo.preload(:attachments)
      |> Enum.reverse()
      |> Enum.reduce(state, fn message, state ->
        Enum.reduce(message.attachments, state, fn attachment, state ->
          {description, state} = describe(attachment, message, user, state)

          line =
            "Attachment #{attachment.id} #{JSON.encode!(attachment.filename)} (#{attachment.content_type}): #{description}"

          update_in(state.contexts, &Map.update(&1, message.id, line, fn previous -> previous <> "\n" <> line end))
        end)
      end)

    {state.contexts, Enum.reverse(state.images)}
  end

  defp describe(attachment, message, user, state) do
    cond do
      invalid_source?(attachment, message, user) ->
        unread("unavailable", state)

      image_over_budget?(attachment, state) ->
        unread("image input budget exceeded", state)

      text?(attachment.content_type) and state.text_bytes >= @text_budget ->
        unread("text input budget exceeded", state)

      attachment.content_type in @image_types or text?(attachment.content_type) ->
        contents(attachment, Attachments.read(user, attachment.thread_id, attachment.id), state)

      true ->
        unread("unsupported format", state)
    end
  end

  defp invalid_source?(attachment, message, user) do
    is_nil(user) or message.kind != "human" or attachment.message_id != message.id or
      attachment.thread_id != message.thread_id
  end

  defp image_over_budget?(attachment, state) do
    attachment.content_type in @image_types and
      (length(state.images) >= @image_count or state.image_bytes + attachment.byte_size > @image_budget)
  end

  defp contents(attachment, {:ok, _attachment, bytes}, state), do: contents(attachment, bytes, state)
  defp contents(_attachment, {:error, _reason}, state), do: unread("unavailable", state)

  defp contents(%{content_type: type}, bytes, state) when type in @image_types do
    if image?(type, bytes) do
      image = %{type: :base64, media_type: type, data: Base.encode64(bytes)}
      number = length(state.images) + 1

      {"image input #{number} follows the transcript",
       %{state | images: [image | state.images], image_bytes: state.image_bytes + byte_size(bytes)}}
    else
      unread("invalid image signature", state)
    end
  end

  defp contents(%{content_type: "application/pdf"}, bytes, state) do
    with true <- String.starts_with?(bytes, "%PDF-"),
         {:ok, path} <- Briefly.create(),
         :ok <- File.write(path, bytes),
         {:ok, [_ | _] = pages} <-
           TextExtractor.extract_pages(path, "application/pdf", "attachment.pdf",
             timeout: 5_000,
             max_pages: 20,
             max_text_bytes: 1_048_576
           ) do
      text = Enum.map_join(pages, "\n\n", & &1.content)
      text_content(text, "PDF text excerpt (at most the first 20 pages; no image/OCR content)", state)
    else
      _ -> unread("PDF text extraction unavailable, unsupported or empty; no OCR", state)
    end
  end

  defp contents(_attachment, bytes, state), do: text_content(bytes, "UTF-8 text excerpt", state)

  defp text_content(text, label, state) do
    if String.valid?(text) and not String.contains?(text, <<0>>) do
      limit = min(@text_per_file, @text_budget - state.text_bytes)
      excerpt = bounded(text, limit)
      suffix = if byte_size(excerpt) < byte_size(text), do: " [truncated]", else: ""
      {"#{label}#{suffix}:\n#{excerpt}", %{state | text_bytes: state.text_bytes + byte_size(excerpt)}}
    else
      unread("not valid UTF-8 text", state)
    end
  end

  defp bounded(text, limit) do
    text
    |> Stream.unfold(&String.next_codepoint/1)
    |> Enum.reduce_while({[], 0}, fn point, {points, size} ->
      if size + byte_size(point) > limit,
        do: {:halt, {points, size}},
        else: {:cont, {[point | points], size + byte_size(point)}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end

  defp unread(reason, state), do: {"contents not read (#{reason}). Do not infer contents from the filename.", state}

  defp text?("application/pdf"), do: true
  defp text?("text/" <> _rest), do: true
  defp text?(type), do: type in @text_types

  defp image?("image/png", <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: true
  defp image?("image/jpeg", <<255, 216, 255, _::binary>>), do: true
  defp image?("image/gif", <<"GIF8", version, "a", _::binary>>) when version in [?7, ?9], do: true
  defp image?("image/webp", <<"RIFF", _size::binary-size(4), "WEBP", _::binary>>), do: true
  defp image?(_type, _bytes), do: false
end
