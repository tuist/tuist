defmodule Condukt.Sandbox.Sync do
  @moduledoc """
  One-way mirrors of a directory from one sandbox to another, as a session
  with a Linux sandbox and a Mac beside it keeps the Mac's worktree current
  before the Mac runs a command (see `Condukt.Sandbox.Lazy`'s `:before_use`).

  A mirror streams the source directory through `Condukt.Sandbox.export/3`
  into `Condukt.Sandbox.import_archive/4`, so nothing is held in memory.
  With `clean: true` the target directory is emptied first, so files deleted
  at the source go at the target too; otherwise the mirror only adds and
  overwrites. Each mirror copies the whole directory: exclude what the
  target rebuilds, such as `.build` or `DerivedData`.
  """

  alias Condukt.Sandbox

  @doc """
  Mirrors `from_path` in `from` to `to_path` in `to`. Options: `:exclude`
  (`tar --exclude` patterns, such as `".git"`), `:clean`, and `:timeout`.
  """
  def mirror(%Sandbox{} = from, from_path, %Sandbox{} = to, to_path, opts \\ []) do
    with :ok <- clean(to, to_path, Keyword.get(opts, :clean, false)) do
      Sandbox.import_archive(to, to_path, Sandbox.export(from, from_path, opts), opts)
    end
  end

  defp clean(_to, _path, false), do: :ok

  defp clean(to, path, true) do
    case Sandbox.exec(to, "rm -rf -- #{q(path)} && mkdir -p -- #{q(path)}", []) do
      {:ok, %{exit_code: 0}} -> :ok
      {:ok, %{output: output}} -> {:error, {:clean_failed, output}}
      error -> error
    end
  end

  defp q(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
