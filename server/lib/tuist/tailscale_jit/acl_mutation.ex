defmodule Tuist.TailscaleJIT.ACLMutation do
  @moduledoc """
  Pure functions for adding / removing a member from a named group
  inside a HuJSON ACL document, preserving everything else byte-for-
  byte. The strategy is intentionally narrow: locate ONLY the
  matched group's array in the source text and rewrite that array,
  rather than parse-and-re-serialize the whole document. This
  preserves comments and unrelated keys (the wider document has
  comments throughout that would be lost by a re-serialization).

  Set semantics: add is idempotent (dedupe), remove of an absent
  member is a no-op success.

  This is the highest-risk piece of the JIT bot. A buggy splice
  silently rewrites the entire prod tailnet policy under an
  approved request and looks like a successful elevation in every
  log. Covered by golden-file tests exercising add/remove on
  populated and empty groups, no-op removes, byte-for-byte
  preservation of comments and unrelated keys, and round-trip
  stability.
  """

  @doc """
  Returns `{:ok, new_doc}` with `member` added to `group_name`'s
  array (deduped if already present), or `{:error, reason}` if the
  group key can't be located.

  `group_name` is the full key as it appears in the document, e.g.
  `"group:tuist-prod-write"`.
  """
  def add_member(doc, group_name, member)
      when is_binary(doc) and is_binary(group_name) and is_binary(member) do
    with {:ok, current} <- list_members(doc, group_name) do
      new_members =
        if member in current do
          current
        else
          current ++ [member]
        end

      replace_group(doc, group_name, new_members)
    end
  end

  @doc """
  Returns `{:ok, new_doc}` with `member` removed from `group_name`'s
  array; no-op success if the member wasn't there. `{:error, ...}`
  only when the group key itself is absent.
  """
  def remove_member(doc, group_name, member)
      when is_binary(doc) and is_binary(group_name) and is_binary(member) do
    with {:ok, current} <- list_members(doc, group_name) do
      replace_group(doc, group_name, List.delete(current, member))
    end
  end

  @doc """
  Returns `{:ok, [member, ...]}` for the named group, or
  `{:error, :group_not_found}` if the group key is absent.
  """
  def list_members(doc, group_name) when is_binary(doc) and is_binary(group_name) do
    case find_group_array(doc, group_name) do
      {:ok, _start, _stop, array_text} -> parse_array(array_text)
      :error -> {:error, :group_not_found}
    end
  end

  defp replace_group(doc, group_name, new_members) do
    case find_group_array(doc, group_name) do
      {:ok, start, stop, _old_array_text} ->
        new_array = render_array(new_members)
        prefix = binary_part(doc, 0, start)
        suffix = binary_part(doc, stop, byte_size(doc) - stop)
        {:ok, prefix <> new_array <> suffix}

      :error ->
        {:error, :group_not_found}
    end
  end

  # Locate the named group's array in the source text and return
  # `{:ok, start, stop, raw_array_text}`. `start` is the byte offset
  # of the opening `[`; `stop` is the byte offset one past the
  # matching `]`. Tailnet group members are emails (no `]`), so the
  # first `]` after the opening `[` is always the matching one.
  defp find_group_array(doc, group_name) do
    key_pattern = ~r/"#{Regex.escape(group_name)}"\s*:\s*\[/

    case Regex.run(key_pattern, doc, return: :index) do
      [{key_offset, key_len}] ->
        array_start = key_offset + key_len - 1
        rest = binary_part(doc, array_start + 1, byte_size(doc) - array_start - 1)

        case :binary.match(rest, "]") do
          {match_at, 1} ->
            array_stop = array_start + 1 + match_at + 1
            array_text = binary_part(doc, array_start, array_stop - array_start)
            {:ok, array_start, array_stop, array_text}

          :nomatch ->
            :error
        end

      nil ->
        :error
    end
  end

  defp parse_array(array_text) do
    inner =
      array_text
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.trim()

    if inner == "" do
      {:ok, []}
    else
      members =
        inner
        |> String.split(",")
        |> Enum.map(&unquote_member/1)
        |> Enum.reject(&(&1 == ""))

      {:ok, members}
    end
  end

  defp unquote_member(raw) do
    raw
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
  end

  defp render_array([]), do: "[]"

  defp render_array(members) when is_list(members) do
    body = members |> Enum.map(&"\"#{&1}\"") |> Enum.join(", ")
    "[" <> body <> "]"
  end
end
