defmodule Noora.MiddleTruncate do
  @moduledoc """
  Truncates text in the middle, keeping its start and end visible.

  ```elixir
  <.middle_truncate value="TuistAcceptanceTests-iOS-Simulator-Release" />
  ```

  Use it for strings where both ends matter, such as schemes, branch and
  project names, IDs, and paths: `TuistAcceptan…-Release`. Use the usual end
  truncation for prose and action labels.

  The string is split into a head, which shrinks with an ellipsis, and a tail
  that always stays visible: the last segment after a `-`, `_`, `/`, `.`, or
  space, or the last 8 characters when there's no separator near the end. It
  adapts to its container in CSS alone. The whole string stays in the page,
  so copying it and screen readers get all of it, and `title` shows it on
  hover when the string is long enough to be split.
  """
  use Phoenix.Component

  @separators ["-", "_", "/", ".", " "]
  @min_tail 4
  @max_tail 16
  @fallback_tail 8

  attr(:value, :string, required: true, doc: "The text to truncate")
  attr(:rest, :global, doc: "Additional HTML attributes")

  def middle_truncate(assigns) do
    {head, tail} = split(assigns.value)
    assigns = assign(assigns, head: head, tail: tail)

    ~H"""
    <span class="noora-middle-truncate" title={if @tail != "", do: @value} {@rest}>
      <span data-part="head">{@head}</span><span
        :if={@tail != ""}
        data-part="tail"
      >{@tail}</span>
    </span>
    """
  end

  @doc """
  Splits `value` into the head that truncates and the tail that stays visible.

      iex> Noora.MiddleTruncate.split("TuistAcceptanceTests-iOS-Simulator-Release")
      {"TuistAcceptanceTests-iOS-Simulator", "-Release"}

      iex> Noora.MiddleTruncate.split("9f8e7d6c5b4a3f2e1d0c")
      {"9f8e7d6c5b4a", "3f2e1d0c"}

      iex> Noora.MiddleTruncate.split("Release")
      {"Release", ""}
  """
  def split(value) when is_binary(value) do
    graphemes = String.graphemes(value)
    count = length(graphemes)

    if count <= @max_tail do
      {value, ""}
    else
      tail_length = separator_tail_length(graphemes, count) || @fallback_tail
      {head, tail} = Enum.split(graphemes, count - tail_length)
      {Enum.join(head), Enum.join(tail)}
    end
  end

  # The tail starts at the last separator whose segment is a readable length.
  defp separator_tail_length(graphemes, count) do
    graphemes
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {grapheme, index} ->
      length = count - index
      if grapheme in @separators and length in @min_tail..@max_tail, do: length
    end)
  end
end
