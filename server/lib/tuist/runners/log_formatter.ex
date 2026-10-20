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
  Groups a flat list of log lines into a tree of `{:line, line}`,
  `{:group, header_line, children}`, and
  `{:action, header, children}` nodes.

  GitHub's runner emits a `##[group]<label>` line at the start of
  each foldable section and a `##[endgroup]` line at the end. We
  preserve the header line on the group node so the template can
  use it as the `<summary>`; the trailing `##[endgroup]` is dropped
  (it's purely a delimiter, never visible in GitHub's own UI).

  A composite action writes each of its steps between
  `##[start-action display=<name>;id=<id>]` and
  `##[end-action id=<id>;outcome=…;conclusion=…;duration_ms=…]`.
  Those become `:action` nodes whose header carries the start line,
  the step `name`, and the `conclusion` / `duration_ms` from the end
  marker, so the template can render them as nested steps the way
  GitHub does. The end marker itself is dropped.

  Groups and actions nest (rare for groups, common for composite
  actions that call other composite actions). An `##[end-action]`
  closes any group still open inside its action. Unterminated groups
  and actions (last batch streamed mid-section) are closed implicitly
  at the end of the list.
  """
  def group_lines(lines) when is_list(lines) do
    lines
    |> walk([], [])
    |> close_open_frames()
    |> Enum.reverse()
  end

  defp walk([], acc, stack), do: {acc, stack}

  defp walk([line | rest], acc, stack) do
    case marker(line) do
      :group_open ->
        walk(rest, [], [{:group, line, acc} | stack])

      :group_close ->
        case stack do
          [{:group, _header, _parent_acc} = frame | stack_rest] -> walk(rest, close_frame(frame, acc), stack_rest)
          _ -> walk(rest, [{:line, line} | acc], stack)
        end

      {:action_start, name} ->
        header = %{line: line, name: name, conclusion: nil, duration_ms: nil}
        walk(rest, [], [{:action, header, acc} | stack])

      {:action_end, result} ->
        if Enum.any?(stack, &match?({:action, _, _}, &1)) do
          {acc, stack} = close_action(acc, stack, result)
          walk(rest, acc, stack)
        else
          walk(rest, [{:line, line} | acc], stack)
        end

      :line ->
        walk(rest, [{:line, line} | acc], stack)
    end
  end

  defp close_action(acc, [{:action, header, parent_acc} | stack_rest], result) do
    {close_frame({:action, Map.merge(header, result), parent_acc}, acc), stack_rest}
  end

  defp close_action(acc, [frame | stack_rest], result) do
    close_action(close_frame(frame, acc), stack_rest, result)
  end

  defp close_open_frames({acc, []}), do: acc

  defp close_open_frames({acc, [frame | stack_rest]}) do
    close_open_frames({close_frame(frame, acc), stack_rest})
  end

  defp close_frame({kind, header, parent_acc}, acc), do: [{kind, header, Enum.reverse(acc)} | parent_acc]

  defp marker(%{message: "##[group]" <> _}), do: :group_open
  defp marker(%{message: "##[endgroup]" <> _}), do: :group_close

  defp marker(%{message: "##[start-action " <> _ = message}) do
    case Regex.run(~r/^##\[start-action display=(.*);id=[^;\]]*\]$/, message, capture: :all_but_first) do
      [name] -> {:action_start, name}
      nil -> :line
    end
  end

  defp marker(%{message: "##[end-action " <> properties}) do
    properties =
      properties
      |> String.trim_trailing("]")
      |> String.split(";")
      |> Map.new(fn property ->
        case String.split(property, "=", parts: 2) do
          [key, value] -> {key, value}
          [key] -> {key, ""}
        end
      end)

    {:action_end,
     %{
       conclusion: Map.get(properties, "conclusion"),
       duration_ms: parse_duration_ms(Map.get(properties, "duration_ms"))
     }}
  end

  defp marker(_line), do: :line

  defp parse_duration_ms(nil), do: nil

  defp parse_duration_ms(value) do
    case Integer.parse(value) do
      {duration_ms, ""} -> duration_ms
      _ -> nil
    end
  end

  @doc """
  The user-visible label of a `##[group]…` header. Strips the
  marker prefix so "##[group]Run echo hi" renders as "Run echo hi".
  """
  def group_label(%{message: "##[group]" <> label}), do: label
  def group_label(%{message: message}), do: message

  # `##[error]`, `##[warning]`, and `##[notice]` are how the runner
  # writes the `::error::` / `::warning::` / `::notice::` workflow
  # commands (and its own failures, e.g. a non-zero exit code) into the
  # log. Workflow commands can carry properties (`file=…,line=…`)
  # before the closing bracket.
  @annotation_pattern ~r/^##\[(error|warning|notice)(?: [^\]]*)?\](.*)$/s

  @doc """
  The annotation kind of a `##[error]…`, `##[warning]…`, or
  `##[notice]…` line (`"error"`, `"warning"`, or `"notice"`), or `nil`
  for any other line. The template tints annotated lines with it, as
  GitHub does.
  """
  def annotation(message) when is_binary(message) do
    case Regex.run(@annotation_pattern, message, capture: :all_but_first) do
      [kind, _text] -> kind
      nil -> nil
    end
  end

  def annotation(_message), do: nil

  @doc """
  Renders a log message as a single iodata `Phoenix.HTML.safe` value
  with one `<span>` per ANSI run. We compose the spans by hand
  (rather than via `~H` / `:for`) so HEEx doesn't insert literal
  newline whitespace between adjacent `<span>` elements — that
  whitespace gets honoured by `white-space: pre-wrap` on the
  surrounding container and shows up as visible blank rows between
  every segment.

  An annotation line renders like GitHub's: the `##[error]` marker
  becomes an `Error:` label (`Warning:` / `Notice:` likewise) in front
  of the message.
  """
  def render_message(message) when is_binary(message) do
    case Regex.run(@annotation_pattern, message, capture: :all_but_first) do
      [kind, text] -> Phoenix.HTML.raw([annotation_label(kind), " ", segments_to_iodata(text)])
      nil -> Phoenix.HTML.raw(segments_to_iodata(message))
    end
  end

  defp annotation_label("error"), do: ~s(<span class="log-annotation-label">Error:</span>)
  defp annotation_label("warning"), do: ~s(<span class="log-annotation-label">Warning:</span>)
  defp annotation_label("notice"), do: ~s(<span class="log-annotation-label">Notice:</span>)

  defp segments_to_iodata(message) do
    message
    |> to_segments()
    |> Enum.map(&segment_to_iodata/1)
  end

  defp segment_to_iodata({text, []}) do
    text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  defp segment_to_iodata({text, classes}) do
    [
      "<span class=\"",
      Enum.intersperse(classes, " "),
      "\">",
      text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string(),
      "</span>"
    ]
  end
end
