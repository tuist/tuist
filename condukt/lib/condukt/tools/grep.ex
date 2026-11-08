defmodule Condukt.Tools.Grep do
  @moduledoc """
  Tool for searching file contents by regular expression.

  Routes through the active `Condukt.Sandbox`. Returns matching lines with
  their file paths and line numbers.

  ## Parameters

  - `pattern` - Regular expression to search for
  - `path` - Directory to search in (optional, defaults to sandbox cwd)
  - `glob` - Glob filter applied to file paths (optional)
  - `case_sensitive` - Whether to match case-sensitively (default: true)
  - `limit` - Maximum matches to return (default: 200)
  """

  use Condukt.Tool

  alias Condukt.Sandbox

  @default_limit 200

  @impl true
  def name, do: "Grep"

  @impl true
  def description do
    """
    Search file contents by regex. Returns matching lines as
    `path:line_number: line`. Filter the file set with `glob` and the search
    root with `path`. Limited to #{@default_limit} matches by default.
    """
    |> String.trim()
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        pattern: %{
          type: "string",
          description: "Regular expression to search for"
        },
        path: %{
          type: "string",
          description: "Directory to search in (optional, defaults to sandbox cwd)"
        },
        glob: %{
          type: "string",
          description: "Glob filter for files to search (e.g. \"**/*.ex\")"
        },
        case_sensitive: %{
          type: "boolean",
          description: "Match case-sensitively (default: true)"
        },
        limit: %{
          type: "number",
          description: "Maximum number of matches to return (default: #{@default_limit})"
        }
      },
      required: ["pattern"]
    }
  end

  @impl true
  def call(%{"pattern" => pattern} = args, context) do
    sandbox = fetch_sandbox!(context)

    opts =
      []
      |> put_if_present(:path, args["path"])
      |> put_if_present(:glob, args["glob"])
      |> Keyword.put(:case_sensitive, Map.get(args, "case_sensitive", true))
      |> Keyword.put(:limit, args["limit"] || @default_limit)

    case Sandbox.grep(sandbox, pattern, opts) do
      {:ok, []} ->
        {:ok, "No matches for #{pattern}"}

      {:ok, matches} ->
        {:ok,
         Enum.map_join(matches, "\n", fn %{path: p, line_number: n, line: line} ->
           "#{p}:#{n}: #{line}"
         end)}

      {:error, :not_supported} ->
        {:error, "Grep is not supported by the active sandbox"}

      {:error, {:invalid_regex, reason, _}} ->
        {:error, "Invalid regex: #{reason}"}

      {:error, reason} ->
        {:error, "Grep failed: #{inspect(reason)}"}
    end
  end

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
