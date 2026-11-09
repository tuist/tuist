defmodule Condukt.Tools.Glob do
  @moduledoc """
  Tool for finding files by glob pattern.

  Routes through the active `Condukt.Sandbox`. Pattern matching uses standard
  shell glob syntax (`**`, `*`, `?`, `[abc]`).

  ## Parameters

  - `pattern` - Glob pattern (e.g. `"**/*.ex"`, `"lib/condukt/tools/*.ex"`)
  - `cwd` - Base directory to glob from (optional, defaults to sandbox cwd)
  - `limit` - Maximum number of paths to return (optional)
  """

  use Condukt.Tool

  alias Condukt.Sandbox

  @default_limit 1_000

  @impl true
  def name, do: "Glob"

  @impl true
  def description do
    """
    Find files by glob pattern (e.g. `**/*.ex`). Returns matching paths
    relative to the search directory. Limited to #{@default_limit} results
    by default.
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
          description: ~s|Glob pattern to match (e.g. "**/*.ex", "lib/**/*.{ex,exs}")|
        },
        cwd: %{
          type: "string",
          description: "Base directory to search in (optional, relative or absolute)"
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
      |> put_if_present(:cwd, args["cwd"])
      |> Keyword.put(:limit, args["limit"] || @default_limit)

    case Sandbox.glob(sandbox, pattern, opts) do
      {:ok, []} ->
        {:ok, "No files matched #{pattern}"}

      {:ok, paths} ->
        {:ok,
         Enum.join(
           ["#{length(paths)} match(es) for #{pattern}:" | paths],
           "\n"
         )}

      {:error, :not_supported} ->
        {:error, "Glob is not supported by the active sandbox"}

      {:error, reason} ->
        {:error, "Glob failed: #{inspect(reason)}"}
    end
  end

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Glob requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end

  defp put_if_present(opts, _key, nil), do: opts
  defp put_if_present(opts, key, value), do: Keyword.put(opts, key, value)
end
