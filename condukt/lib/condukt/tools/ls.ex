defmodule Condukt.Tools.Ls do
  @moduledoc """
  Tool for listing a directory, after pi's `ls` tool.

  Routes through `Condukt.Sandbox.list_dir/2`. Entries are sorted
  alphabetically, case-insensitively, with a `/` after directories, and
  include dotfiles. Output is cut to 500 entries (by default) or 50KB.

  ## Parameters

  - `path` - Directory to list (optional, defaults to sandbox cwd)
  - `limit` - Maximum number of entries to return (default: 500)
  """

  use Condukt.Tool

  alias Condukt.Sandbox
  alias Condukt.Tools.Truncate

  @default_limit 500

  @impl true
  def name(opts), do: Keyword.get(opts, :name, "Ls")

  # Reads change nothing, so an interrupted call can simply run again.
  @impl true
  def replay_safe?, do: true

  @impl true
  def read_only?(_opts), do: true

  @impl true
  def description(_opts) do
    "List directory contents. Returns entries sorted alphabetically, with '/' suffix for directories. " <>
      "Includes dotfiles. Output is truncated to #{@default_limit} entries or " <>
      "#{div(Truncate.max_bytes(), 1024)}KB (whichever is hit first)."
  end

  @impl true
  def parameters(_opts) do
    %{
      type: "object",
      properties: %{
        path: %{type: "string", description: "Directory to list (default: current directory)"},
        limit: %{type: "number", description: "Maximum number of entries to return (default: #{@default_limit})"}
      },
      required: []
    }
  end

  @impl true
  def call(args, context) do
    sandbox = fetch_sandbox!(context)
    path = args["path"] || "."
    limit = if is_number(args["limit"]), do: max(trunc(args["limit"]), 1), else: @default_limit

    case Sandbox.list_dir(sandbox, path) do
      {:ok, []} ->
        {:ok, "(empty directory)"}

      {:ok, entries} ->
        {:ok, format(entries, limit)}

      {:error, :enoent} ->
        {:error, "Path not found: #{path}"}

      {:error, :enotdir} ->
        {:error, "Not a directory: #{path}"}

      {:error, reason} ->
        {:error, "Cannot read directory #{path}: #{inspect(reason)}"}
    end
  end

  defp format(entries, limit) do
    names =
      entries
      |> Enum.sort_by(&String.downcase(&1.name))
      |> Enum.map(&if(&1.type == :directory, do: &1.name <> "/", else: &1.name))

    truncation = names |> Enum.take(limit) |> Enum.join("\n") |> Truncate.head(max_lines: :infinity)

    Truncate.with_notices(truncation.content, [
      length(names) > limit && "#{limit} entries limit reached. Use limit=#{limit * 2} for more",
      truncation.truncated && "#{Truncate.format_size(Truncate.max_bytes())} limit reached"
    ])
  end

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Ls requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end
end
