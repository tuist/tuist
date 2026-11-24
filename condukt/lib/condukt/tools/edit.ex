defmodule Condukt.Tools.Edit do
  @moduledoc """
  Tool for making surgical edits to a file, after pi's `edit` tool.

  One call makes one or more replacements in one file. Each `oldText` is
  matched against the original file, not incrementally, must appear exactly
  once, and must not overlap another edit's.

  Matching tolerates what models get wrong: line endings (CRLF files are
  matched as LF and keep their CRLFs), a byte order mark, and, when the
  exact text is not found, trailing whitespace, smart quotes, Unicode dashes,
  and special spaces. A fuzzy match rewrites only the lines it touches.

  All filesystem access goes through the active `Condukt.Sandbox`: the tool
  reads the file, applies the edits, and writes it back. A session never
  runs two calls that change files at once, so nothing else writes the file
  in between.

  ## Parameters

  - `path` - Path to the file to edit
  - `edits` - List of `%{"oldText" => ..., "newText" => ...}` replacements

  A single `oldText`/`newText` pair (or `old_text`/`new_text`) at the top
  level is accepted as a one-element `edits`.
  """

  use Condukt.Tool

  alias Condukt.Sandbox

  @impl true
  def name(opts), do: Keyword.get(opts, :name, "Edit")

  @impl true
  def description(_opts) do
    "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, " <>
      "non-overlapping region of the original file. If two changes affect the same block or nearby lines, " <>
      "merge them into one edit instead of emitting overlapping edits. Do not include large unchanged " <>
      "regions just to connect distant changes."
  end

  @impl true
  def parameters(_opts) do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description: "Path to the file to edit (relative or absolute)"
        },
        edits: %{
          type: "array",
          description:
            "One or more targeted replacements. Each edit is matched against the original file, not " <>
              "incrementally. Do not include overlapping or nested edits. If two changes touch the same " <>
              "block or nearby lines, merge them into one edit instead.",
          items: %{
            type: "object",
            properties: %{
              oldText: %{
                type: "string",
                description:
                  "Exact text for one targeted replacement. It must be unique in the original file and " <>
                    "must not overlap with any other edits[].oldText in the same call."
              },
              newText: %{type: "string", description: "Replacement text for this targeted edit."}
            },
            required: ["oldText", "newText"]
          }
        }
      },
      required: ["path", "edits"]
    }
  end

  @impl true
  def call(%{"path" => path} = args, context) do
    sandbox = fetch_sandbox!(context)

    case edits(args) do
      [] ->
        {:error, "Edit tool input is invalid. edits must contain at least one replacement."}

      edits ->
        edit(sandbox, path, edits)
    end
  end

  defp edit(sandbox, path, edits) do
    with {:ok, raw} <- read(sandbox, path),
         {bom, content} = split_bom(raw),
         normalized = normalize_to_lf(content),
         {:ok, base, updated, replacements} <- apply_edits(normalized, edits, path),
         final = bom <> if(content == normalized, do: updated, else: apply_to_original(content, replacements)),
         :ok <- write(sandbox, path, final) do
      {:ok, "Successfully replaced #{length(edits)} block(s) in #{path}.\n\n" <> diff(base, replacements)}
    end
  end

  defp read(sandbox, path) do
    case Sandbox.read(sandbox, path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, "File not found: #{path}"}
      {:error, reason} -> {:error, "Could not edit file: #{path}. #{inspect(reason)}."}
    end
  end

  defp write(sandbox, path, content) do
    case Sandbox.write(sandbox, path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "Cannot write to #{path}: #{inspect(reason)}"}
    end
  end

  # Some models send `edits` as a JSON string or a single object, or the
  # replacement at the top level.
  defp edits(args) do
    edits =
      case args["edits"] do
        list when is_list(list) -> list
        %{} = edit -> [edit]
        json when is_binary(json) -> decode_edits(json)
        _ -> []
      end

    top_level =
      for {old, new} <- [{"oldText", "newText"}, {"old_text", "new_text"}], is_binary(args[old]), do: {old, new}

    edits = Enum.map(edits, &pair/1) ++ Enum.map(top_level, fn {old, new} -> {args[old], args[new]} end)
    if Enum.all?(edits, &match?({old, new} when is_binary(old) and is_binary(new), &1)), do: edits, else: []
  end

  defp decode_edits(json) do
    case JSON.decode(json) do
      {:ok, list} when is_list(list) -> list
      {:ok, %{} = edit} -> [edit]
      _ -> []
    end
  end

  defp pair(%{"oldText" => old, "newText" => new}), do: {old, new}
  defp pair(%{"old_text" => old, "new_text" => new}), do: {old, new}
  defp pair(_edit), do: nil

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Edit requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end

  # ============================================================================
  # Matching, after pi's edit-diff.ts. Offsets are byte offsets.
  # ============================================================================

  defp split_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: {<<0xEF, 0xBB, 0xBF>>, rest}
  defp split_bom(content), do: {"", content}

  defp normalize_to_lf(text), do: text |> String.replace("\r\n", "\n") |> String.replace("\r", "\n")

  @doc false
  def normalize_for_fuzzy_match(text) do
    text
    |> nfkc()
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim_trailing/1)
    |> String.replace(~r/[\x{2018}\x{2019}\x{201A}\x{201B}]/u, "'")
    |> String.replace(~r/[\x{201C}\x{201D}\x{201E}\x{201F}]/u, "\"")
    |> String.replace(~r/[\x{2010}-\x{2015}\x{2212}]/u, "-")
    |> String.replace(~r/[\x{00A0}\x{2002}-\x{200A}\x{202F}\x{205F}\x{3000}]/u, " ")
  end

  defp nfkc(text) do
    case :unicode.characters_to_nfkc_binary(text) do
      normalized when is_binary(normalized) -> normalized
      _invalid -> text
    end
  end

  defp apply_edits(content, edits, path) do
    edits = Enum.map(edits, fn {old, new} -> {normalize_to_lf(old), normalize_to_lf(new)} end)
    total = length(edits)

    # Fuzzy matching normalizes Unicode, so text that is not UTF-8, such as a
    # Latin-1 file, is matched exactly only.
    normalize =
      if Enum.all?([content | Enum.map(edits, &elem(&1, 0))], &String.valid?/1),
        do: &normalize_for_fuzzy_match/1,
        else: &Function.identity/1

    with :ok <- check_not_empty(edits, path, total),
         fuzzy? = Enum.any?(edits, fn {old, _new} -> :binary.match(content, old) == :nomatch end),
         search = if(fuzzy?, do: normalize.(content), else: content),
         {:ok, matches} <- match_all(search, edits, normalize, path, total),
         :ok <- check_overlaps(matches, path),
         replacements = if(fuzzy?, do: widen_to_lines(content, search, matches), else: matches),
         updated = replace(content, replacements),
         false <- updated == content do
      {:ok, content, updated, replacements}
    else
      true -> {:error, no_change_error(path, total)}
      error -> error
    end
  end

  defp check_not_empty(edits, path, total) do
    case Enum.find_index(edits, fn {old, _new} -> old == "" end) do
      nil -> :ok
      _index when total == 1 -> {:error, "oldText must not be empty in #{path}."}
      index -> {:error, "edits[#{index}].oldText must not be empty in #{path}."}
    end
  end

  # Each edit is found exactly in `search`, else in its normalized form, and
  # must occur once there. Text that normalizes to nothing, such as
  # whitespace only, is counted exactly.
  defp match_all(search, edits, normalize, path, total) do
    normalized_search = normalize.(search)

    edits
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{old, new}, index}, {:ok, acc} ->
      {found, occurrences} = find(search, normalized_search, old, normalize.(old))

      cond do
        found == :nomatch ->
          {:halt, {:error, not_found_error(path, index, total)}}

        occurrences > 1 ->
          {:halt, {:error, duplicate_error(path, index, total, occurrences)}}

        true ->
          {at, length} = found
          {:cont, {:ok, [%{index: index, at: at, length: length, new: new} | acc]}}
      end
    end)
    |> case do
      {:ok, matches} -> {:ok, Enum.sort_by(matches, & &1.at)}
      error -> error
    end
  end

  defp find(search, _normalized_search, old, ""), do: {:binary.match(search, old), length(:binary.matches(search, old))}

  defp find(search, normalized_search, old, normalized_old) do
    found = with :nomatch <- :binary.match(search, old), do: :binary.match(search, normalized_old)
    {found, length(:binary.matches(normalized_search, normalized_old))}
  end

  defp check_overlaps(matches, path) do
    matches
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [a, b] -> a.at + a.length > b.at end)
    |> case do
      nil ->
        :ok

      [a, b] ->
        {:error,
         "edits[#{a.index}] and edits[#{b.index}] overlap in #{path}. Merge them into one edit or target disjoint regions."}
    end
  end

  # Replacements matched in the fuzzy-normalized text become replacements of
  # whole lines of the original: the lines they touch are rewritten from the
  # normalized text, all other lines keep their bytes.
  defp widen_to_lines(content, search, matches) do
    original_lines = line_spans(content)
    search_lines = line_spans(search)

    matches
    |> Enum.reduce([], fn match, groups ->
      {first, last} = line_range(search_lines, match)

      case groups do
        [%{last: prev_last} = group | rest] when first < prev_last ->
          [%{group | last: max(prev_last, last), matches: group.matches ++ [match]} | rest]

        _ ->
          [%{first: first, last: last, matches: [match]} | groups]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn group ->
      {search_start, _} = Enum.at(search_lines, group.first)
      {_, search_end} = Enum.at(search_lines, group.last - 1)
      {original_start, _} = Enum.at(original_lines, group.first)
      {_, original_end} = Enum.at(original_lines, group.last - 1)
      text = binary_part(search, search_start, search_end - search_start)
      shifted = Enum.map(group.matches, &%{&1 | at: &1.at - search_start})
      %{at: original_start, length: original_end - original_start, new: replace(text, shifted)}
    end)
  end

  defp line_spans(text) do
    {spans, _offset} =
      ~r/[^\n]*\n|[^\n]+/
      |> Regex.scan(text)
      |> Enum.map_reduce(0, fn [line], offset -> {{offset, offset + byte_size(line)}, offset + byte_size(line)} end)

    spans
  end

  defp line_range(lines, %{at: at, length: length}) do
    first = Enum.find_index(lines, fn {start, stop} -> at >= start and at < stop end)
    stop = at + length
    last = Enum.find_index(Enum.drop(lines, first), fn {_start, line_end} -> line_end >= stop end) + first
    {first, last + 1}
  end

  defp replace(content, replacements) do
    {parts, position} =
      Enum.reduce(replacements, {[], 0}, fn r, {parts, position} ->
        {[r.new, binary_part(content, position, r.at - position) | parts], r.at + r.length}
      end)

    IO.iodata_to_binary(Enum.reverse([binary_part(content, position, byte_size(content) - position) | parts]))
  end

  # Applies replacements matched in the LF-normalized text to the original,
  # whose CRLFs are one byte longer, as pi's `applyReplacementsToOriginal`
  # does. Untouched text keeps its bytes; new line breaks take the ending of
  # the line the replacement starts on.
  defp apply_to_original(original, replacements) do
    # The n-th CRLF (0-based) at original offset p is at p - n in the normalized text.
    normalized_crlfs =
      original |> :binary.matches("\r\n") |> Enum.with_index() |> Enum.map(fn {{p, _}, n} -> p - n end)

    to_original = fn offset -> offset + Enum.count(normalized_crlfs, &(&1 < offset)) end

    {parts, position} =
      Enum.reduce(replacements, {[], 0}, fn r, {parts, position} ->
        start = to_original.(r.at)

        new =
          case line_ending_at(original, start) do
            "\n" -> r.new
            ending -> String.replace(r.new, "\n", ending)
          end

        {[new, binary_part(original, position, start - position) | parts], to_original.(r.at + r.length)}
      end)

    [binary_part(original, position, byte_size(original) - position) | parts]
    |> Enum.reverse()
    |> join_parts()
  end

  # A CR before a seam and an LF after it would merge into one CRLF line
  # break, as when a kept lone CR is followed by inserted text that starts
  # with LF; an added LF keeps them two line breaks, as the diff shows.
  defp join_parts(parts) do
    {acc, _ends_with_cr?} =
      Enum.reduce(parts, {[], false}, fn
        "", state ->
          state

        part, {acc, ends_with_cr?} ->
          acc = if ends_with_cr? and String.starts_with?(part, "\n"), do: ["\n" | acc], else: acc
          {[part | acc], String.ends_with?(part, "\r")}
      end)

    acc |> Enum.reverse() |> IO.iodata_to_binary()
  end

  # The ending of the line containing `offset`: its own LF or CRLF, or the
  # previous line's for an unterminated last line. A lone CR only counts in
  # files without any LF (classic Mac line endings).
  defp line_ending_at(content, offset) do
    line_feed =
      case :binary.match(content, "\n", scope: {offset, byte_size(content) - offset}) do
        {at, 1} -> at
        :nomatch -> last_line_feed(content, offset)
      end

    cond do
      line_feed == nil -> if String.contains?(content, "\r"), do: "\r", else: "\n"
      line_feed > 0 and :binary.at(content, line_feed - 1) == ?\r -> "\r\n"
      true -> "\n"
    end
  end

  defp last_line_feed(content, offset) do
    case :binary.matches(content, "\n", scope: {0, min(offset + 1, byte_size(content))}) do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  defp not_found_error(path, _index, 1),
    do:
      "Could not find the exact text in #{path}. The old text must match exactly including all whitespace and newlines."

  defp not_found_error(path, index, _total),
    do:
      "Could not find edits[#{index}] in #{path}. The oldText must match exactly including all whitespace and newlines."

  defp duplicate_error(path, _index, 1, count),
    do:
      "Found #{count} occurrences of the text in #{path}. The text must be unique. Please provide more context to make it unique."

  defp duplicate_error(path, index, _total, count),
    do:
      "Found #{count} occurrences of edits[#{index}] in #{path}. Each oldText must be unique. Please provide more context to make it unique."

  defp no_change_error(path, 1),
    do:
      "No changes made to #{path}. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."

  defp no_change_error(path, _total), do: "No changes made to #{path}. The replacements produced identical content."

  # The replaced lines of the LF-normalized file and their replacements, with
  # line numbers in the old and new file.
  defp diff(base, replacements) do
    {hunks, _delta} =
      Enum.map_reduce(replacements, 0, fn r, delta ->
        line = count_newlines(binary_part(base, 0, r.at)) + 1
        old = binary_part(base, r.at, r.length)
        old_lines = old |> String.trim_trailing("\n") |> String.split("\n")
        new_lines = if r.new == "", do: [], else: r.new |> String.trim_trailing("\n") |> String.split("\n")

        hunk =
          Enum.with_index(old_lines, &"-#{line + &2} #{&1}") ++
            Enum.with_index(new_lines, &"+#{line + delta + &2} #{&1}")

        {Enum.join(hunk, "\n"), delta + count_newlines(r.new) - count_newlines(old)}
      end)

    "```diff\n" <> Enum.join(hunks, "\n ...\n") <> "\n```"
  end

  defp count_newlines(text), do: length(:binary.matches(text, "\n"))
end
