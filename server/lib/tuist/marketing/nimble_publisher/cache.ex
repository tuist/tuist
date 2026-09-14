defmodule Tuist.Marketing.NimblePublisher.Cache do
  @moduledoc false

  alias Tuist.ContentCache
  alias Tuist.Marketing.NimblePublisher.Builder

  def start_link(_opts) do
    ContentCache.start_link(name: __MODULE__)
  end

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  end

  def entries(key, opts) do
    # In dev the content is read at runtime rather than compiled in, so nothing
    # marks the module stale when a source file changes. Keying the cache on the
    # sources' paths and mtimes makes an edit produce a different key, which
    # rebuilds instead of serving the copy built at boot.
    ContentCache.get(__MODULE__, {key, fingerprint(opts)}, fn -> Builder.build!(opts) end)
  end

  defp fingerprint(opts) do
    opts
    |> Keyword.fetch!(:from)
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn path ->
      case File.stat(path, time: :posix) do
        {:ok, %File.Stat{mtime: mtime, size: size}} -> {path, mtime, size}
        _ -> {path, nil, nil}
      end
    end)
    |> :erlang.term_to_binary()
    |> :erlang.md5()
  end

  def reload do
    ContentCache.reload(__MODULE__)
  end
end
