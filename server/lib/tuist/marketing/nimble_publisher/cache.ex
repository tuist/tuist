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
    # In dev, browser live reload can request content before ContentFileWatcher
    # clears the cache after its 100ms delay. Fingerprinting source paths, mtimes,
    # and sizes lets that request rebuild changed content without waiting for
    # the watcher, closing the race between browser reload and invalidation.
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
