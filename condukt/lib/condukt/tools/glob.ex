defmodule Condukt.Tools.Glob do
  @moduledoc """
  Tool for finding files by glob pattern, after pi's `find` tool.

  Routes through the active `Condukt.Sandbox`. Pattern matching uses standard
  shell glob syntax (`**`, `*`, `?`, `[abc]`). A pattern without a `/`, such
  as `*.ex`, matches names at any depth; one with a `/` is anchored at the
  search directory.

  ## Parameters

  - `pattern` - Glob pattern (e.g. `"*.ex"`, `"lib/condukt/tools/*.ex"`)
  - `path` - Directory to search in (optional, defaults to sandbox cwd)
  - `limit` - Maximum number of paths to return (default: 1000)
  """

  use Condukt.Tool

  alias Condukt.Sandbox
  alias Condukt.Tools.Truncate

  @default_limit 1_000

  @impl true
  def name(opts), do: Keyword.get(opts, :name, "Glob")

  # Reads change nothing, so an interrupted call can simply run again.
  @impl true
  def replay_safe?, do: true

  @impl true
  def read_only?(_opts), do: true

  @impl true
  def description(_opts) do
    "Search for files by glob pattern. Returns matching file paths relative to the search directory. " <>
      "Output is truncated to #{@default_limit} results or #{div(Truncate.max_bytes(), 1024)}KB " <>
      "(whichever is hit first)."
  end

  @impl true
  def parameters(_opts) do
    %{
      type: "object",
      properties: %{
        pattern: %{
          type: "string",
          description:
            "Glob pattern relative to the search directory, e.g. 'src/**/*.ts'. " <>
              "Without '/', e.g. '*.ts', it matches file names at any depth"
        },
        path: %{type: "string", description: "Directory to search in (default: current directory)"},
        limit: %{type: "number", description: "Maximum number of results (default: #{@default_limit})"}
      },
      required: ["pattern"]
    }
  end

  @impl true
  def call(%{"pattern" => pattern} = args, context) do
    sandbox = fetch_sandbox!(context)
    limit = if is_number(args["limit"]), do: max(trunc(args["limit"]), 1), else: @default_limit
    pattern = String.replace(pattern, ~r{\A(\./)+}, "")
    pattern = if String.contains?(pattern, "/"), do: pattern, else: "**/" <> pattern

    # One result past the limit tells "exactly N matches" apart from "more than N".
    opts = put_if_present([limit: limit + 1], :cwd, args["path"] || args["cwd"])

    case Sandbox.glob(sandbox, pattern, opts) do
      {:ok, []} ->
        {:ok, "No files found matching pattern"}

      {:ok, paths} ->
        {:ok, format(paths, limit)}

      {:error, :not_supported} ->
        {:error, "Glob is not supported by the active sandbox"}

      {:error, reason} ->
        {:error, "Glob failed: #{inspect(reason)}"}
    end
  end

  defp format(paths, limit) do
    truncation = paths |> Enum.take(limit) |> Enum.join("\n") |> Truncate.head(max_lines: :infinity)

    Truncate.with_notices(truncation.content, [
      length(paths) > limit && "#{limit} results limit reached. Use limit=#{limit * 2} for more, or refine pattern",
      truncation.truncated && "#{Truncate.format_size(Truncate.max_bytes())} limit reached"
    ])
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
