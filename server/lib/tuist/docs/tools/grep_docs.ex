defmodule Tuist.Docs.Tools.GrepDocs do
  @moduledoc false

  use Condukt.Tool

  alias Tuist.Docs.AskAgent

  require Logger

  @default_max_results 12
  @max_max_results 30
  @snippet_max_chars 240
  @rg_timeout_ms 5_000
  @max_query_length 200

  @impl Condukt.Tool
  def name, do: "grep_docs"

  @impl Condukt.Tool
  def description do
    """
    Search the Tuist documentation for a literal string or regex. Returns up
    to max_results matches as objects with `slug` (the docs URL slug, e.g.
    "/en/docs/guides/install-tuist"), `line`, and `snippet`. Use this to
    ground answers in the documentation.
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
        locale: %{
          type: "string",
          description: ~s{Docs locale to search (e.g. "en"). Defaults to "en".},
          default: "en"
        },
        max_results: %{
          type: "integer",
          description: "Maximum number of matches to return (default 12, max 30).",
          default: @default_max_results
        }
      },
      required: ["query"]
    }
  end

  @impl Condukt.Tool
  def call(%{"query" => query} = args, _context) when is_binary(query) and query != "" do
    locale = Map.get(args, "locale", "en")
    max_results = args |> Map.get("max_results", @default_max_results) |> normalize_max()
    query = String.slice(query, 0, @max_query_length)

    case locale_root(locale) do
      {:ok, root} ->
        matches = ripgrep(query, root, max_results)
        Logger.info("[ask] grep_docs query=#{inspect(query)} locale=#{locale} count=#{length(matches)}")
        {:ok, %{matches: matches, count: length(matches)}}

      {:error, message} ->
        Logger.info("[ask] grep_docs query=#{inspect(query)} locale=#{locale} error=#{message}")
        {:ok, %{error: message, matches: [], count: 0}}
    end
  end

  def call(_args, _ctx), do: {:ok, %{error: "query is required", matches: [], count: 0}}

  defp normalize_max(n) when is_integer(n) and n > 0, do: min(n, @max_max_results)
  defp normalize_max(_), do: @default_max_results

  defp locale_root(locale) when is_binary(locale) do
    if locale =~ ~r/\A[a-z]{2,5}\z/ do
      root = Path.join(AskAgent.docs_root(), locale)

      if File.dir?(root) do
        {:ok, root}
      else
        {:error, "unknown locale"}
      end
    else
      {:error, "invalid locale"}
    end
  end

  defp ripgrep(query, root, max_results) do
    if System.find_executable("rg") do
      try do
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
            |> Enum.map(&parse_line(&1, root))
            |> Enum.reject(&is_nil/1)

          _ ->
            []
        end
      rescue
        _ -> []
      end
    else
      []
    end
  end

  defp parse_line(line, root) do
    case String.split(line, ":", parts: 3) do
      [path, line_no, snippet] ->
        %{
          slug: filesystem_path_to_slug(path, root),
          line: parse_int(line_no),
          snippet: truncate(snippet)
        }

      _ ->
        nil
    end
  end

  defp filesystem_path_to_slug(absolute_path, root) do
    relative = Path.relative_to(absolute_path, root)
    locale = Path.basename(root)

    relative
    |> String.replace_suffix(".md", "")
    |> String.replace_suffix("/index", "")
    |> then(fn p -> "/" <> locale <> "/docs/" <> p end)
    |> String.replace_suffix("/", "")
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
