defmodule Condukt.SessionStore.Disk do
  @moduledoc """
  Disk-backed session store using Erlang term serialization.

  By default snapshots are written to `.condukt/session.store` in the
  configured working directory. Override with `path: ...`.

  The journal is an append-only file next to the snapshot, at the snapshot's
  path with `.journal` added, or at `journal_path: ...`. Each record is one
  length-prefixed Erlang term. Appends survive the process dying, not the
  machine losing power: like snapshots, they are not flushed with `fsync`.
  A record torn by a crash mid-append is dropped, and the file truncated to
  the last whole record, the next time the journal is loaded.
  """

  @behaviour Condukt.SessionStore

  alias Condukt.SessionStore.Snapshot

  @version 1

  @impl true
  def load(opts) do
    path = path(opts)

    case File.read(path) do
      {:ok, binary} ->
        with {:ok, payload} <- decode(binary) do
          extract_snapshot(payload)
        end

      {:error, :enoent} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def save(%Snapshot{} = snapshot, opts) do
    path = path(opts)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, encode(snapshot))
    end
  end

  @impl true
  def clear(opts) do
    path = path(opts)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def append_journal(records, opts) when is_list(records) do
    path = journal_path(opts)
    frames = Enum.map(records, &frame/1)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      with_file(path, &write_at_end(&1, frames))
    end
  end

  # A write that fails partway is cut back off, so the fragment cannot end up
  # in the middle of the journal once a later append succeeds.
  defp write_at_end(file, frames) do
    with {:ok, eof} <- :file.position(file, :eof) do
      case :file.write(file, frames) do
        :ok ->
          :ok

        {:error, reason} ->
          _ = truncate_at(file, eof)
          {:error, reason}
      end
    end
  end

  @impl true
  def load_journal(opts) do
    path = journal_path(opts)

    case File.read(path) do
      {:ok, binary} -> read_journal(path, binary)
      {:error, :enoent} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_journal(path, binary) do
    with {:ok, records, valid_size} <- parse_journal(binary, [], 0),
         :ok <- drop_torn_tail(path, valid_size, byte_size(binary)) do
      {:ok, records}
    end
  end

  # Appends after a torn record would leave it in the middle of the file, so
  # a journal that cannot be cut back is an error rather than a partial read.
  defp drop_torn_tail(_path, size, size), do: :ok
  defp drop_torn_tail(path, valid_size, _size), do: with_file(path, &truncate_at(&1, valid_size))

  @impl true
  def clear_journal(opts) do
    case File.rm(journal_path(opts)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp frame(record) do
    binary = :erlang.term_to_binary(record)
    [<<byte_size(binary)::unsigned-32>>, binary]
  end

  defp parse_journal(<<size::unsigned-32, binary::binary-size(size), rest::binary>>, records, offset) do
    case decode_record(binary) do
      {:ok, record} -> parse_journal(rest, [record | records], offset + 4 + size)
      {:error, _reason} -> {:error, :invalid_journal}
    end
  end

  # Whatever is left is either nothing or a record the process died writing.
  defp parse_journal(_rest, records, offset), do: {:ok, Enum.reverse(records), offset}

  defp truncate_at(file, size) do
    with {:ok, ^size} <- :file.position(file, size), do: :file.truncate(file)
  end

  # Read and write without `append`, which would not let a write be cut back,
  # and without truncating the file on open.
  defp with_file(path, fun) do
    with {:ok, file} <- :file.open(path, [:read, :write, :binary, :raw]) do
      try do
        fun.(file)
      after
        :file.close(file)
      end
    end
  end

  defp journal_path(opts) do
    Keyword.get_lazy(opts, :journal_path, fn -> path(opts) <> ".journal" end)
  end

  defp path(opts) do
    Keyword.get_lazy(opts, :path, fn ->
      cwd = Keyword.fetch!(opts, :cwd)

      case Keyword.get(opts, :id) do
        nil -> Path.join([cwd, ".condukt", "session.store"])
        id -> Path.join([cwd, ".condukt", "sessions", "#{id}.store"])
      end
    end)
  end

  # Without `:safe`, unlike the snapshot: a record can hold an atom the
  # restarted VM has not loaded yet, such as a tool's error reason, and one
  # such record would otherwise make the session unable to start. The journal
  # is this store's own file, written by the session it belongs to.
  defp decode_record(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  catch
    :error, _reason ->
      {:error, :invalid_journal}
  end

  defp encode(snapshot) do
    :erlang.term_to_binary(%{version: @version, snapshot: snapshot})
  end

  defp decode(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  catch
    :error, _reason ->
      {:error, :invalid_snapshot}
  end

  defp extract_snapshot(%{version: @version, snapshot: %Snapshot{} = snapshot}), do: {:ok, snapshot}
  defp extract_snapshot(%Snapshot{} = snapshot), do: {:ok, snapshot}
  defp extract_snapshot(_payload), do: {:error, :invalid_snapshot}
end
