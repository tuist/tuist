defmodule Tuist.Docs.Tools.ReadFile do
  @moduledoc false

  use Condukt.Tool

  alias Tuist.Docs.AskAgent
  alias Tuist.Docs.Tools.SafePath

  @max_lines 400

  @impl Condukt.Tool
  def name, do: "read_file"

  @impl Condukt.Tool
  def description do
    """
    Read a slice of a docs page or source file. `path` is interpreted relative
    to one of the allowed roots: pass the docs slug (e.g.
    "en/guides/install-tuist.md") to read documentation, or a sources-relative
    path (e.g. "cli/Sources/TuistKit/Foo.swift") to read source. At most 400
    lines are returned.
    """
  end

  @impl Condukt.Tool
  def parameters do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description: "Relative path to the file."
        },
        start_line: %{
          type: "integer",
          description: "1-indexed first line to return (default 1)."
        },
        end_line: %{
          type: "integer",
          description: "1-indexed last line to return (default start_line + 399)."
        }
      },
      required: ["path"]
    }
  end

  @impl Condukt.Tool
  def call(%{"path" => path} = args, _context) when is_binary(path) and path != "" do
    start_line = args |> Map.get("start_line", 1) |> normalize_line(1)
    end_line = args |> Map.get("end_line", start_line + @max_lines - 1) |> normalize_line(start_line)
    end_line = min(end_line, start_line + @max_lines - 1)

    with {:ok, absolute} <- resolve_path(path),
         {:ok, contents} <- File.read(absolute) do
      slice =
        contents
        |> String.split("\n")
        |> Enum.slice((start_line - 1)..(end_line - 1))
        |> Enum.join("\n")

      {:ok, %{path: path, start_line: start_line, end_line: end_line, content: slice}}
    else
      {:error, :enoent} -> {:ok, %{error: "file not found", path: path}}
      {:error, :unsafe_path} -> {:ok, %{error: "path not allowed", path: path}}
      {:error, reason} -> {:ok, %{error: inspect(reason), path: path}}
    end
  end

  def call(_args, _ctx), do: {:ok, %{error: "path is required"}}

  defp normalize_line(n, _floor) when is_integer(n) and n >= 1, do: n
  defp normalize_line(_, floor), do: floor

  defp resolve_path(path) do
    if Regex.match?(~r/\A[a-z]{2,5}\//, path) do
      SafePath.resolve(AskAgent.docs_root(), path)
    else
      SafePath.resolve(AskAgent.sources_root(), path)
    end
  end
end
