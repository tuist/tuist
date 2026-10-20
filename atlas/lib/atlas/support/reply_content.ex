defmodule Atlas.Support.ReplyContent do
  @moduledoc false

  @gmail_reply_delimiter ~r/^On .+ wrote:\s*(?:\n\s*)+(?=>)/im
  @outlook_reply_delimiter ~r/^(?:_{3,}|-{3,})\s*(?:Original Message)?\s*$/im
  @outlook_headers_delimiter ~r/^From:\s.+\n(?:Sent|Date):\s.+\nTo:\s.+\n(?:Cc:\s.+\n)?Subject:\s.+$/im
  @quoted_line ~r/^>.*$/m
  @signature_delimiter ~r/^--\s*$/m
  @inline_attachment ~r/\[cid:([^\]]+)\]/i

  def visible(body) when is_binary(body) do
    visible =
      body
      |> visible_before_quoted_content()
      |> String.replace(@inline_attachment, "")
      |> String.trim()

    if visible == "", do: String.trim(body), else: visible
  end

  def visible(_body), do: ""

  def inline_attachment_ids(body) when is_binary(body) do
    body
    |> visible_before_quoted_content()
    |> then(&Regex.scan(@inline_attachment, &1))
    |> Enum.map(fn [_, content_id] -> content_id end)
    |> Enum.uniq()
  end

  def inline_attachment_ids(_body), do: []

  defp visible_before_quoted_content(body) do
    body
    |> before(@gmail_reply_delimiter)
    |> before(@outlook_reply_delimiter)
    |> before(@outlook_headers_delimiter)
    |> before(@quoted_line)
    |> before(@signature_delimiter)
  end

  defp before(body, delimiter) do
    case Regex.run(delimiter, body, return: :index) do
      [{index, _length} | _captures] -> binary_part(body, 0, index)
      nil -> body
    end
  end
end
