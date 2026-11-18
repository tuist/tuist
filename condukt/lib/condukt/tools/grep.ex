defmodule Condukt.Tools.Grep do
  @moduledoc """
  Tool for searching file contents, after pi's `grep` tool.

  Routes through the active `Condukt.Sandbox`. Returns matching lines as
  `path:line: text`, and the lines around them, when `context` asks for
  them, as `path-line- text`. Long lines are cut to 500 characters, and the
  output to 100 matches (by default) or 50KB, with a notice saying what was
  cut.

  ## Parameters

  - `pattern` - Regular expression (or literal string with `literal`)
  - `path` - Directory to search in (optional, defaults to sandbox cwd)
  - `glob` - Glob filter relative to `path`; one without `/`, such as
    `*.ex`, matches file names at any depth
  - `ignoreCase` - Match case-insensitively (default: false)
  - `literal` - Treat the pattern as a literal string (default: false)
  - `context` - Lines to show before and after each match (default: 0)
  - `limit` - Maximum matches to return (default: 100)
  """

  use Condukt.Tool

  alias Condukt.Sandbox
  alias Condukt.Tools.Truncate

  @default_limit 100

  @impl true
  def name(opts), do: Keyword.get(opts, :name, "Grep")

  # Reads change nothing, so an interrupted call can simply run again.
  @impl true
  def replay_safe?, do: true

  @impl true
  def read_only?(_opts), do: true

  @impl true
  def description(_opts) do
    "Search file contents for a pattern. Returns matching lines with file paths and line numbers. " <>
      "Output is truncated to #{@default_limit} matches or #{div(Truncate.max_bytes(), 1024)}KB " <>
      "(whichever is hit first). Long lines are truncated to #{Truncate.max_line_chars()} chars."
  end

  @impl true
  def parameters(_opts) do
    %{
      type: "object",
      properties: %{
        pattern: %{type: "string", description: "Search pattern (regex or literal string)"},
        path: %{type: "string", description: "Directory to search (default: current directory)"},
        glob: %{
          type: "string",
          description:
            "Filter files by glob pattern relative to path, e.g. 'src/**/*.ts'. " <>
              "Without '/', e.g. '*.ts', it matches file names at any depth"
        },
        ignoreCase: %{type: "boolean", description: "Case-insensitive search (default: false)"},
        literal: %{type: "boolean", description: "Treat pattern as literal string instead of regex (default: false)"},
        context: %{type: "number", description: "Number of lines to show before and after each match (default: 0)"},
        limit: %{type: "number", description: "Maximum number of matches to return (default: #{@default_limit})"}
      },
      required: ["pattern"]
    }
  end

  @impl true
  def call(%{"pattern" => pattern} = args, context) do
    sandbox = fetch_sandbox!(context)
    limit = positive(args["limit"], @default_limit)
    lines_around = positive(args["context"], 0)
    pattern = if args["literal"], do: escape(pattern), else: pattern
    ignore_case? = args["ignoreCase"] == true or args["case_sensitive"] == false

    opts =
      [case_sensitive: not ignore_case?, limit: limit + 1]
      |> put_if_present(:path, args["path"])
      |> put_if_present(:glob, args["glob"] && String.replace(args["glob"], ~r{\A(!?)(\./)+}, "\\1"))

    case Sandbox.grep(sandbox, pattern, opts) do
      {:ok, []} ->
        {:ok, "No matches found"}

      {:ok, matches} ->
        {:ok, format(sandbox, args["path"], Enum.take(matches, limit), length(matches) > limit, limit, lines_around)}

      {:error, :not_supported} ->
        {:error, "Grep is not supported by the active sandbox"}

      {:error, {:invalid_regex, reason, _}} ->
        {:error, "Invalid regex: #{reason}"}

      {:error, reason} ->
        {:error, "Grep failed: #{inspect(reason)}"}
    end
  end

  defp format(sandbox, base, matches, limit_reached?, limit, lines_around) do
    rows = if lines_around > 0, do: with_context(sandbox, base, matches, lines_around), else: rows(matches)

    {lines, cut?} =
      Enum.map_reduce(rows, false, fn {path, number, text, match?}, cut? ->
        {text, cut} = text |> String.trim_trailing("\r") |> Truncate.line()
        separator = if match?, do: ":", else: "-"
        {"#{path}#{separator}#{number}#{separator} #{text}", cut? or cut}
      end)

    truncation = Truncate.head(Enum.join(lines, "\n"), max_lines: :infinity)

    notices = [
      limit_reached? && "#{limit} matches limit reached. Use limit=#{limit * 2} for more, or refine pattern",
      truncation.truncated && "#{Truncate.format_size(Truncate.max_bytes())} limit reached",
      cut? && "Some lines truncated to #{Truncate.max_line_chars()} chars. Use read tool to see full lines"
    ]

    Truncate.with_notices(truncation.content, notices)
  end

  defp rows(matches), do: Enum.map(matches, &{&1.path, &1.line_number, &1.line, true})

  # The lines around the matches, read from each matched file. Windows that
  # touch merge, and a match inside another's window shows as a match.
  defp with_context(sandbox, base, matches, lines_around) do
    matches
    |> Enum.chunk_by(& &1.path)
    |> Enum.flat_map(fn [%{path: path} | _] = file_matches ->
      case Sandbox.read(sandbox, join(base, path)) do
        {:ok, content} -> file_rows(path, content, file_matches, lines_around)
        {:error, _reason} -> rows(file_matches)
      end
    end)
  end

  # Some sandboxes report matches under the search path, others relative to it.
  defp join(nil, path), do: path
  defp join(base, path), do: if(Path.type(path) == :absolute, do: path, else: Path.join(base, path))

  # Matched lines show as the search found them. A sandbox may count lines
  # differently from `\\n` splits, as one that breaks lines at a lone CR
  # does, or the file may have changed since the search, so context lines
  # past the file's end are left out.
  defp file_rows(path, content, matches, lines_around) do
    lines = content |> String.split("\n") |> List.to_tuple()
    matched = Map.new(matches, &{&1.line_number, &1.line})

    matches
    |> Enum.flat_map(&Range.new(max(&1.line_number - lines_around, 1), &1.line_number + lines_around, 1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn number ->
      cond do
        Map.has_key?(matched, number) -> [{path, number, matched[number], true}]
        number <= tuple_size(lines) -> [{path, number, elem(lines, number - 1), false}]
        true -> []
      end
    end)
  end

  # Escapes what PCRE, Python's `re` and POSIX extended regexes all treat as
  # special, so a literal pattern means the same on every sandbox.
  defp escape(pattern), do: String.replace(pattern, ~r/[.^$*+?()\[\]{}|\\]/, "\\\\\\0")

  defp positive(value, _default) when is_number(value) and value >= 1, do: trunc(value)
  defp positive(value, default) when is_number(value) and default > 0, do: 1
  defp positive(_value, default), do: default

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Grep requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)
end
