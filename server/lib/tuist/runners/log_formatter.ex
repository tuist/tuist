defmodule Tuist.Runners.LogFormatter do
  @moduledoc """
  Render-side helpers for GitHub Actions log lines.

  The Logs API returns text that has been written with a terminal
  consumer in mind: ANSI SGR sequences for colour and weight,
  `##[group]…##[endgroup]` markers for collapsible sections,
  `##[command]` / `##[notice]` annotations, etc. Rendered raw, those
  artefacts add a lot of noise (`[36;1m`, literal group markers).
  Rendered as GitHub does — colour spans, foldable groups — they
  read the way a developer expects.

  This module is the host-side translator: a flat list of
  `%{line_number, ts, message}` rows becomes a tree the HEEx
  template can walk, with each line's `message` split into ANSI
  segments. Mark-up generation lives in the template; we only
  return data.
  """

  @doc """
  Strips ANSI SGR escape sequences from `message` and returns the
  plain text. Use for places that don't (yet) render colour — the
  download endpoint, the live-tail stream, the search results.
  """
  def strip_ansi(message) when is_binary(message) do
    Regex.replace(~r/\x1b\[[0-9;]*m/, message, "")
  end

  @doc """
  Splits a message into a list of `{text, classes}` tuples, one per
  ANSI SGR run. `classes` is a (possibly empty) list of CSS class
  names that the template wraps in `<span class="…">`.

  We only translate the SGR codes GitHub Actions actually emits:
  the basic 8 foreground colours, their bright variants, and `bold`.
  Everything else is dropped (the run continues with the prior
  style); the text is preserved either way.
  """
  def to_segments(message) when is_binary(message) do
    message
    |> do_segments([], MapSet.new(), [])
    |> Enum.reverse()
    |> Enum.reject(fn {text, _} -> text == "" end)
  end

  defp do_segments(<<"\e[", rest::binary>>, buf, style, acc) do
    case extract_sgr(rest) do
      {codes, rest2} ->
        new_style = apply_codes(style, codes)
        acc2 = flush(buf, style, acc)
        do_segments(rest2, [], new_style, acc2)

      :error ->
        # Not a well-formed SGR — emit `\e[` as literal text.
        do_segments(rest, ["\e[" | buf], style, acc)
    end
  end

  defp do_segments(<<c::utf8, rest::binary>>, buf, style, acc) do
    do_segments(rest, [<<c::utf8>> | buf], style, acc)
  end

  defp do_segments("", buf, style, acc) do
    flush(buf, style, acc)
  end

  defp extract_sgr(binary) do
    case Regex.run(~r/^([0-9;]*)m(.*)$/s, binary, capture: :all_but_first) do
      [codes, rest] ->
        parsed =
          codes
          |> String.split(";", trim: true)
          |> Enum.flat_map(fn code ->
            case Integer.parse(code) do
              {n, ""} -> [n]
              _ -> []
            end
          end)

        # An empty `\e[m` is equivalent to `\e[0m` — reset.
        {if(parsed == [], do: [0], else: parsed), rest}

      _ ->
        :error
    end
  end

  defp apply_codes(style, codes) do
    Enum.reduce(codes, style, fn code, acc ->
      case code do
        0 -> MapSet.new()
        1 -> MapSet.put(acc, "ansi-bold")
        n when n in 30..37 -> set_fg(acc, "ansi-fg-#{n - 30}")
        n when n in 90..97 -> set_fg(acc, "ansi-fg-bright-#{n - 90}")
        # Anything else (background colours, 256-colour, italic, …)
        # is ignored: the run keeps the prior style. The user-
        # visible text is unaffected.
        _ -> acc
      end
    end)
  end

  defp set_fg(style, class) do
    style
    |> Enum.reject(&String.starts_with?(&1, "ansi-fg-"))
    |> MapSet.new()
    |> MapSet.put(class)
  end

  defp flush([], _style, acc), do: acc

  defp flush(buf, style, acc) do
    text = buf |> Enum.reverse() |> IO.iodata_to_binary()
    [{text, Enum.sort(MapSet.to_list(style))} | acc]
  end

  @doc """
  Groups a flat list of log lines into a tree of `{:line, line}` and
  `{:group, header_line, children}` nodes by walking
  `##[group]…##[endgroup]` markers.

  GitHub's runner emits a `##[group]<label>` line at the start of
  each foldable section and a `##[endgroup]` line at the end. We
  preserve the header line on the group node so the template can
  use it as the `<summary>`; the trailing `##[endgroup]` is dropped
  (it's purely a delimiter, never visible in GitHub's own UI).

  Nested groups are supported (rare, but possible: `actions/cache`
  sometimes nests). Unterminated groups (last batch streamed
  mid-group) are closed implicitly at the end of the list.
  """
  def group_lines(lines) when is_list(lines) do
    lines
    |> walk([], [])
    |> close_open_groups()
    |> Enum.reverse()
  end

  defp walk([], acc, stack), do: {acc, stack}

  defp walk([line | rest], acc, stack) do
    cond do
      group_open?(line) ->
        # Open a new group: stash the current acc onto the stack
        # along with the header line, then start a fresh acc for
        # the group's children.
        walk(rest, [], [{line, acc} | stack])

      group_close?(line) and stack != [] ->
        # Close the innermost open group: wrap its accumulated
        # children into a `{:group, header, children}` node and
        # splice it into the parent's acc.
        [{header, parent_acc} | stack_rest] = stack
        children = Enum.reverse(acc)
        walk(rest, [{:group, header, children} | parent_acc], stack_rest)

      true ->
        walk(rest, [{:line, line} | acc], stack)
    end
  end

  defp close_open_groups({acc, []}), do: acc

  defp close_open_groups({acc, [{header, parent_acc} | stack_rest]}) do
    children = Enum.reverse(acc)
    close_open_groups({[{:group, header, children} | parent_acc], stack_rest})
  end

  defp group_open?(%{message: message}) when is_binary(message) do
    String.starts_with?(message, "##[group]")
  end

  defp group_open?(_), do: false

  defp group_close?(%{message: message}) when is_binary(message) do
    message == "##[endgroup]" or String.starts_with?(message, "##[endgroup]")
  end

  defp group_close?(_), do: false

  @doc """
  The user-visible label of a `##[group]…` header. Strips the
  marker prefix so "##[group]Run echo hi" renders as "Run echo hi".
  """
  def group_label(%{message: "##[group]" <> label}), do: label
  def group_label(%{message: message}), do: message

  @doc """
  Renders a log message as a single iodata `Phoenix.HTML.safe` value
  with one `<span>` per ANSI run. We compose the spans by hand
  (rather than via `~H` / `:for`) so HEEx doesn't insert literal
  newline whitespace between adjacent `<span>` elements — that
  whitespace gets honoured by `white-space: pre-wrap` on the
  surrounding container and shows up as visible blank rows between
  every segment.
  """
  def render_message(message) when is_binary(message) do
    message
    |> to_segments()
    |> Enum.map(&segment_to_iodata/1)
    |> Phoenix.HTML.raw()
  end

  defp segment_to_iodata({text, []}) do
    Phoenix.HTML.html_escape(text) |> Phoenix.HTML.safe_to_string()
  end

  defp segment_to_iodata({text, classes}) do
    [
      "<span class=\"",
      Enum.intersperse(classes, " "),
      "\">",
      Phoenix.HTML.html_escape(text) |> Phoenix.HTML.safe_to_string(),
      "</span>"
    ]
  end
end
