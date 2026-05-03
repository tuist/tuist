defmodule Tuist.Docs.Tools.GrepSources do
  @moduledoc false

  use Condukt.Tool

  alias Tuist.Docs.AskAgent
  alias Tuist.Docs.Tools.SafePath

  require Logger

  @default_max_results 15
  @max_max_results 40
  @snippet_max_chars 240
  @rg_timeout_ms 8_000
  @max_query_length 200
  @scopes ~w(cli server cache kura app android tuist_common noora handbook all)

  @impl Condukt.Tool
  def name, do: "grep_sources"

  @impl Condukt.Tool
  def description do
    """
    Search the Tuist project sources for a literal string or regex. Use this
    when the user is asking about CLI behaviour, server behaviour, or other
    implementation details that aren't covered by the docs. Returns up to
    max_results matches with `path` (relative to the sources root), `line`,
    and `snippet`.
    """
  end

  @impl Condukt.Tool
  def parameters do
    %{
      type: "object",
      properties: %{
        query: %{
          type: "string",
          description: "Pattern to search for. Treated as a regex by ripgrep."
        },
        scope: %{
          type: "string",
          description:
            "Limit search to one subproject. One of: " <>
              Enum.join(@scopes, ", ") <> ". Defaults to \"all\".",
          default: "all"
        },
        max_results: %{
          type: "integer",
          description: "Maximum number of matches to return (default 15, max 40).",
          default: @default_max_results
        }
      },
      required: ["query"]
    }
  end

  @impl Condukt.Tool
  def call(%{"query" => query} = args, _context) when is_binary(query) and query != "" do
    scope = Map.get(args, "scope", "all")
    max_results = args |> Map.get("max_results", @default_max_results) |> normalize_max()
    sources_root = AskAgent.sources_root()
    query = String.slice(query, 0, @max_query_length)

    case scope_root(sources_root, scope) do
      {:ok, root} ->
        matches = ripgrep(query, root, sources_root, max_results)
        Logger.info("[ask] grep_sources query=#{inspect(query)} scope=#{scope} count=#{length(matches)}")
        {:ok, %{matches: matches, count: length(matches)}}

      {:error, message} ->
        Logger.info("[ask] grep_sources query=#{inspect(query)} scope=#{scope} error=#{message}")
        {:ok, %{error: message, matches: [], count: 0}}
    end
  end

  def call(_args, _ctx), do: {:ok, %{error: "query is required", matches: [], count: 0}}

  defp normalize_max(n) when is_integer(n) and n > 0, do: min(n, @max_max_results)
  defp normalize_max(_), do: @default_max_results

  defp scope_root(sources_root, "all"), do: {:ok, sources_root}

  defp scope_root(sources_root, scope) when scope in @scopes do
    case SafePath.resolve(sources_root, scope) do
      {:ok, path} ->
        if File.dir?(path), do: {:ok, path}, else: {:error, "scope not available"}

      _ ->
        {:error, "scope not available"}
    end
  end

  defp scope_root(_root, _other), do: {:error, "invalid scope"}

  defp ripgrep(query, root, base, max_results) do
    if System.find_executable("rg") do
      do_ripgrep(query, root, base, max_results)
    else
      []
    end
  end

  defp do_ripgrep(query, root, base, max_results) do
    case MuonTrap.cmd(
           "rg",
           [
             "--no-heading",
             "--line-number",
             "--with-filename",
             "--max-count",
             "5",
             "--max-columns",
             "400",
             "--smart-case",
             "--glob",
             "!**/.git/**",
             "--glob",
             "!**/node_modules/**",
             "--glob",
             "!**/_build/**",
             "--glob",
             "!**/deps/**",
             "--glob",
             "!**/.build/**",
             "--",
             query,
             root
           ],
           stderr_to_stdout: true,
           timeout: @rg_timeout_ms
         ) do
      {output, code} when code in [0, 1] ->
        output
        |> String.split("\n", trim: true)
        |> Enum.take(max_results)
        |> Enum.map(&parse_line(&1, base))
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp parse_line(line, base) do
    case String.split(line, ":", parts: 3) do
      [path, line_no, snippet] ->
        %{
          path: Path.relative_to(path, base),
          line: parse_int(line_no),
          snippet: truncate(snippet)
        }

      _ ->
        nil
    end
  end

  defp parse_int(string) do
    case Integer.parse(string) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp truncate(string) do
    trimmed = String.trim(string)

    if String.length(trimmed) > @snippet_max_chars do
      String.slice(trimmed, 0, @snippet_max_chars) <> "…"
    else
      trimmed
    end
  end
end
