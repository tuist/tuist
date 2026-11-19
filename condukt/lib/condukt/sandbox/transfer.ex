defmodule Condukt.Sandbox.Transfer do
  @moduledoc """
  Moves directories in and out of a sandbox as tar archives, a chunk at a
  time, so an `.xcresult` bundle or a built `.app` never sits in memory
  whole.

  Both directions run `tar` in the sandbox as a process
  (`c:Condukt.Sandbox.start_process/4`), base64-encoded so the bytes survive
  sandboxes whose output is text, such as a remote exec. `export/3` follows
  the process's log; `import_archive/4` writes the archive to its stdin, so
  it needs `c:Condukt.Sandbox.write_process/4` too. The sandbox needs `tar`
  and `base64`.

      sandbox
      |> Condukt.Sandbox.export("build/App.app")
      |> Stream.into(File.stream!("App.app.tar"))
      |> Stream.run()

      Condukt.Sandbox.import_archive(mac, "work/repo", Condukt.Sandbox.export(linux, "repo"))
  """

  alias Condukt.Sandbox

  @read_bytes 512 * 1024
  @write_bytes 48 * 1024
  @wait 1_000
  @timeout to_timeout(hour: 1)

  @doc """
  A stream of the tar archive of `path`, relative to the sandbox's working
  directory. Enumerating it raises when the sandbox cannot run processes or
  `tar` fails.

  Options: `:timeout` in milliseconds (default one hour), and `:exclude`, a
  list of `tar --exclude` patterns.
  """
  def export(%Sandbox{} = sandbox, path, opts \\ []) when is_binary(path) do
    Stream.resource(
      fn -> start_export(sandbox, path, opts) end,
      &next_chunk/1,
      fn {sandbox, id, _offset, _rest} -> Sandbox.stop_process(sandbox, id) end
    )
  end

  @doc """
  Unpacks `chunks`, an enumerable of a tar archive's bytes such as `export/3`
  returns, into the directory `path`, creating it. Returns `:ok` or
  `{:error, reason}`.
  """
  def import_archive(%Sandbox{} = sandbox, path, chunks, opts \\ []) when is_binary(path) do
    id = process_id("import")
    command = "mkdir -p #{q(path)} && base64 -d | tar -C #{q(path)} -xf -"

    with true <- Sandbox.supports?(sandbox, :write_process, 4) || {:error, :not_supported},
         :ok <- Sandbox.start_process(sandbox, id, command, stdin: true, timeout: opts[:timeout] || @timeout) do
      try do
        with {:ok, _offset} <- write_all(sandbox, id, chunks),
             :ok <- Sandbox.write_process(sandbox, id, "", close: true) do
          await_exit(sandbox, id)
        end
      after
        Sandbox.stop_process(sandbox, id)
      end
    end
  end

  defp start_export(sandbox, path, opts) do
    id = process_id("export")
    excludes = opts |> Keyword.get(:exclude, []) |> Enum.map_join(&" --exclude=#{q(&1)}")
    command = "tar -C #{q(path)}#{excludes} -cf - . 2>/dev/null | base64 | tr -d '\\n'; exit ${PIPESTATUS[0]}"

    case Sandbox.start_process(sandbox, id, command, timeout: opts[:timeout] || @timeout) do
      :ok -> {sandbox, id, 0, ""}
      {:error, reason} -> raise "could not export #{path}: #{inspect(reason)}"
    end
  end

  defp next_chunk({_sandbox, _id, :done, _rest} = acc), do: {:halt, acc}

  defp next_chunk({sandbox, id, offset, rest}) do
    case Sandbox.read_process(sandbox, id, offset, max_bytes: @read_bytes, wait: @wait) do
      {:ok, %{output: output, offset: next, size: size, status: status}} ->
        encoded = rest <> output
        whole = byte_size(encoded) - rem(byte_size(encoded), 4)
        <<now::binary-size(^whole), later::binary>> = encoded
        chunk = Base.decode64!(now)

        cond do
          status == :running or next < size -> {[chunk], {sandbox, id, next, later}}
          status == {:exited, 0} and later == "" -> {[chunk], {sandbox, id, :done, ""}}
          true -> raise "export failed: #{inspect(status)}"
        end

      {:error, reason} ->
        raise "export failed: #{inspect(reason)}"
    end
  end

  # Base64 of pieces of three bytes each concatenates into one valid stream.
  defp write_all(sandbox, id, chunks) do
    chunks
    |> Stream.transform(
      fn -> "" end,
      fn chunk, rest ->
        bytes = rest <> chunk
        whole = byte_size(bytes) - rem(byte_size(bytes), @write_bytes)
        <<now::binary-size(^whole), later::binary>> = bytes
        {for(<<piece::binary-size(@write_bytes) <- now>>, do: piece), later}
      end,
      fn rest -> {if(rest == "", do: [], else: [rest]), ""} end,
      fn _rest -> :ok end
    )
    |> Enum.reduce_while({:ok, 0}, fn piece, {:ok, offset} -> write(sandbox, id, piece, offset) end)
  end

  defp write(sandbox, id, piece, offset) do
    data = Base.encode64(piece) <> "\n"

    case Sandbox.write_process(sandbox, id, data, offset: offset) do
      :ok -> {:cont, {:ok, offset + byte_size(data)}}
      error -> {:halt, error}
    end
  end

  defp await_exit(sandbox, id) do
    case Sandbox.read_process(sandbox, id, 0, max_bytes: 4096, wait: @wait) do
      {:ok, %{status: :running}} -> await_exit(sandbox, id)
      {:ok, %{status: {:exited, 0}}} -> :ok
      {:ok, %{status: status, output: output}} -> {:error, {:import_failed, status, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_id(kind), do: "condukt-transfer:#{kind}:#{System.unique_integer([:positive])}:#{node()}"

  defp q(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
