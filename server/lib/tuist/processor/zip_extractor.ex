defmodule Tuist.Processor.ZipExtractor do
  @moduledoc """
  Extracts uploaded zip archives within a size and entry budget.

  Archives are tenant-controlled. `:zip.unzip/2` inflates each entry to the end
  of its compressed stream and never compares the result with the size the
  archive declares, so a small, highly compressed upload could fill the
  processor's disk. This checks the declared total size and entry count from
  the central directory before writing anything, then streams each entry
  through zlib and stops as soon as it inflates past its declared size, so the
  declared total bounds what reaches the disk.

  Errors keep the shapes `:zip` uses for malformed archives (`:bad_eocd`,
  `:bad_central_directory`, also returned for entries whose data overlaps,
  `:bad_local_file_header`, `{name, :bad_crc}`, ...), plus
  `:archive_too_large` and `{:unsafe_entry_name, name}`. Errors reading the
  archive file itself, such as `:eio`, pass through unchanged so callers retry
  them instead of treating the upload as corrupt.
  """

  import Bitwise

  @local_file_header_magic 0x04034B50
  @data_descriptor_magic 0x08074B50
  @stored 0
  @deflated 8
  @read_block_size 64 * 1024

  def extract(archive_path, destination, opts) do
    max_bytes = Keyword.fetch!(opts, :max_bytes)
    max_entries = Keyword.fetch!(opts, :max_entries)

    with {:ok, listing} <- :zip.list_dir(~c"#{archive_path}"),
         entries = for({:zip_file, _, _, _, _, _} = entry <- listing, do: entry),
         :ok <- check_budget(entries, max_bytes, max_entries),
         {:ok, fd} <- :file.open(archive_path, [:read, :binary, :raw]) do
      try do
        with :ok <- check_layout(fd, entries) do
          Enum.reduce_while(entries, :ok, fn entry, :ok ->
            case extract_entry(fd, entry, destination) do
              :ok -> {:cont, :ok}
              error -> {:halt, error}
            end
          end)
        end
      after
        :file.close(fd)
      end
    end
  end

  defp check_budget(entries, max_bytes, max_entries) do
    declared_bytes = Enum.reduce(entries, 0, fn {:zip_file, _, info, _, _, _}, acc -> acc + elem(info, 1) end)

    if length(entries) > max_entries or declared_bytes > max_bytes do
      {:error, :archive_too_large}
    else
      :ok
    end
  end

  # The central directory may point several records at the same compressed
  # data, which would write it once per record. The archives clients upload
  # store each entry's data once, so entries whose local header and data
  # overlap another entry's are rejected as a malformed central directory.
  defp check_layout(fd, entries) do
    entries
    |> Enum.sort_by(fn {:zip_file, _, _, _, offset, _} -> offset end)
    |> Enum.reduce_while({:ok, 0}, fn {:zip_file, _, _, _, offset, comp_size}, {:ok, previous_end} ->
      case local_header(fd, offset) do
        {:ok, %{data_offset: data_offset}} when offset >= previous_end -> {:cont, {:ok, data_offset + comp_size}}
        {:ok, _header} -> {:halt, {:error, :bad_central_directory}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _end} -> :ok
      error -> error
    end
  end

  defp local_header(fd, offset) do
    case :file.pread(fd, offset, 30) do
      {:ok,
       <<@local_file_header_magic::32-little, _version::16, flags::16-little, method::16-little, _time::16, _date::16,
         crc::32-little, _comp_size::32, _uncomp_size::32, name_length::16-little, extra_length::16-little>>} ->
        {:ok, %{flags: flags, method: method, crc: crc, data_offset: offset + 30 + name_length + extra_length}}

      {:error, _} = error ->
        error

      _ ->
        {:error, :bad_local_file_header}
    end
  end

  defp extract_entry(fd, {:zip_file, name, info, _comment, offset, comp_size}, destination) do
    name = List.to_string(name)

    case Path.safe_relative(name) do
      {:ok, relative} ->
        path = Path.join(destination, relative)

        if String.ends_with?(name, "/") do
          File.mkdir_p(path)
        else
          with :ok <- File.mkdir_p(Path.dirname(path)) do
            extract_file(fd, name, path, offset, comp_size, elem(info, 1))
          end
        end

      :error ->
        {:error, {:unsafe_entry_name, name}}
    end
  end

  defp extract_file(fd, name, path, offset, comp_size, declared_size) do
    with {:ok, %{flags: flags, method: method, crc: crc, data_offset: data_offset}} <- local_header(fd, offset),
         {:ok, actual_crc} <- write_entry(fd, path, method, data_offset, comp_size, declared_size),
         {:ok, expected_crc} <- expected_crc(fd, flags, crc, data_offset + comp_size) do
      if actual_crc == expected_crc, do: :ok, else: {:error, {String.to_charlist(name), :bad_crc}}
    end
  end

  # Entries written with a trailing data descriptor (general purpose bit 3)
  # carry their checksum after the data, optionally behind a signature.
  defp expected_crc(fd, flags, _crc, descriptor_offset) when (flags &&& 8) == 8 do
    case :file.pread(fd, descriptor_offset, 8) do
      {:ok, <<@data_descriptor_magic::32-little, crc::32-little>>} -> {:ok, crc}
      {:ok, <<crc::32-little, _::binary>>} -> {:ok, crc}
      {:error, _} = error -> error
      _ -> {:error, :bad_local_file_header}
    end
  end

  defp expected_crc(_fd, _flags, crc, _descriptor_offset), do: {:ok, crc}

  defp write_entry(fd, path, method, data_offset, comp_size, declared_size) when method in [@stored, @deflated] do
    z = :zlib.open()

    try do
      if method == @deflated, do: :zlib.inflateInit(z, -15)

      result =
        File.open(path, [:write, :binary, :raw], fn out ->
          state = %{fd: fd, out: out, z: z, method: method, limit: declared_size, written: 0, crc: :erlang.crc32(<<>>)}
          copy(state, data_offset, comp_size)
        end)

      case result do
        {:ok, {:ok, crc}} -> {:ok, crc}
        {:ok, {:error, _} = error} -> error
        {:error, _} = error -> error
      end
    rescue
      # zlib raises on data that is not a valid deflate stream.
      ErlangError -> {:error, :bad_local_file_header}
    after
      :zlib.close(z)
    end
  end

  defp write_entry(_fd, _path, _method, _data_offset, _comp_size, _declared_size), do: {:error, :bad_local_file_header}

  defp copy(state, _offset, 0), do: {:ok, state.crc}

  defp copy(state, offset, remaining) do
    case :file.pread(state.fd, offset, min(remaining, @read_block_size)) do
      {:ok, chunk} ->
        with {:ok, state} <- output(state, chunk) do
          copy(state, offset + byte_size(chunk), remaining - byte_size(chunk))
        end

      {:error, _} = error ->
        error

      :eof ->
        {:error, :bad_local_file_header}
    end
  end

  defp output(%{method: @stored} = state, chunk), do: write(state, chunk)

  defp output(%{method: @deflated} = state, chunk), do: inflate(state, :zlib.safeInflate(state.z, chunk))

  # `safeInflate` hands back output a bounded piece at a time, so a highly
  # compressed chunk is checked against the limit before it is all in memory.
  defp inflate(state, {:continue, data}) do
    with {:ok, state} <- write(state, data), do: inflate(state, :zlib.safeInflate(state.z, []))
  end

  defp inflate(state, {:finished, data}), do: write(state, data)

  defp inflate(_state, _result), do: {:error, :bad_local_file_header}

  defp write(state, data) do
    written = state.written + IO.iodata_length(data)

    if written > state.limit do
      {:error, :archive_too_large}
    else
      case :file.write(state.out, data) do
        :ok -> {:ok, %{state | written: written, crc: :erlang.crc32(state.crc, data)}}
        {:error, _} = error -> error
      end
    end
  end
end
