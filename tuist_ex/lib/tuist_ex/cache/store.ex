defmodule TuistEx.Cache.Store do
  @moduledoc false

  alias TuistEx.Cache.Key

  @max_files 50_000
  @max_manifest_bytes 10_000_000
  @max_bundle_bytes 64 * 1024 * 1024
  @max_duration_ms 4_294_967_295

  def max_bundle_bytes, do: @max_bundle_bytes

  def export_bundle(root, key) do
    entry = Path.join(root, key)
    binary = File.read!(Path.join(entry, "manifest.json"))
    if byte_size(binary) > @max_manifest_bytes, do: throw(:invalid_entry)
    manifest = JSON.decode!(binary)
    files = manifest["files"]

    if manifest["key"] != key or not is_list(files) or length(files) > @max_files,
      do: throw(:invalid_entry)

    {records, contents, _size} =
      Enum.reduce(files, {[], [], 0}, fn file, {records, contents, size} ->
        validate_path!(file["path"])

        case file["type"] do
          "directory" ->
            {[file | records], contents, size}

          "file" ->
            regular_path!(Path.join(entry, "files"), Path.split(file["path"]))
            path = Path.join([entry, "files", file["path"]])
            if size + File.stat!(path).size > @max_bundle_bytes, do: throw(:invalid_entry)
            data = File.read!(path)
            if Key.digest(data) != file["digest"], do: throw(:invalid_entry)

            {[Map.put(file, "size_bytes", byte_size(data)) | records], [data | contents],
             size + byte_size(data)}

          _ ->
            throw(:invalid_entry)
        end
      end)

    metadata = JSON.encode!(Map.put(manifest, "files", Enum.reverse(records)))

    data =
      IO.iodata_to_binary([
        <<byte_size(metadata)::unsigned-big-32>>,
        metadata,
        Enum.reverse(contents)
      ])

    if byte_size(data) > @max_bundle_bytes, do: throw(:invalid_entry)
    {:ok, data}
  rescue
    error -> {:error, error}
  catch
    :invalid_entry -> {:error, :invalid_entry}
  end

  def restore_bundle(root, key, binary, build, source, validate \\ fn _ -> true end) do
    staging = sibling(root, "fetch")
    entry = Path.join(staging, key)

    try do
      with true <- byte_size(binary) <= @max_bundle_bytes,
           <<size::unsigned-big-32, rest::binary>> <- binary,
           true <- size <= @max_manifest_bytes and size <= byte_size(rest),
           metadata = binary_part(rest, 0, size),
           contents = binary_part(rest, size, byte_size(rest) - size),
           %{"key" => ^key, "files" => files} <- JSON.decode!(metadata),
           true <- is_list(files) and length(files) <= @max_files do
        File.mkdir_p!(Path.join(entry, "files"))

        remainder =
          Enum.reduce(files, contents, fn file, data ->
            validate_path!(file["path"])

            case file do
              %{"type" => "directory"} ->
                data

              %{"type" => "file", "size_bytes" => bytes}
              when is_integer(bytes) and bytes >= 0 and bytes <= byte_size(data) ->
                content = binary_part(data, 0, bytes)
                tail = binary_part(data, bytes, byte_size(data) - bytes)
                path = Path.join([entry, "files", file["path"]])
                File.mkdir_p!(Path.dirname(path))
                File.write!(path, content)
                tail

              _ ->
                throw(:invalid_entry)
            end
          end)

        if remainder != "", do: throw(:invalid_entry)
        File.write!(Path.join(entry, "manifest.json"), metadata)

        case restore_with_metrics(staging, key, build, source, validate) do
          {:ok, duration, metrics} ->
            File.mkdir_p!(root)
            publish_entry(entry, Path.join(root, key), root, key, source, validate)
            {:ok, duration, metrics}

          :miss ->
            :miss
        end
      else
        _ -> :miss
      end
    rescue
      _ -> :miss
    catch
      :invalid_entry -> :miss
    after
      File.rm_rf(staging)
    end
  end

  def restore(root, key, build, source) do
    case restore_with_metrics(root, key, build, source) do
      {:ok, duration, _metrics} -> {:ok, duration}
      :miss -> :miss
    end
  end

  def restore_with_metrics(root, key, build, source, validate \\ fn _ -> true end) do
    started = System.monotonic_time(:microsecond)
    entry = Path.join(root, key)
    staging = sibling(build, "restore")

    try do
      with {:ok, binary} <- File.read(Path.join(entry, "manifest.json")),
           true <- byte_size(binary) <= @max_manifest_bytes,
           {:ok, manifest} <- JSON.decode(binary),
           %{
             "version" => 1,
             "key" => ^key,
             "files" => files,
             "links" => links,
             "compile_duration_ms" => duration
           } <- manifest,
           true <- is_list(files) and length(files) <= @max_files,
           true <- is_list(links) and length(links) <= 3,
           true <- is_integer(duration) and duration >= 0 and duration <= @max_duration_ms do
        File.mkdir_p!(staging)

        bytes =
          Enum.reduce(files, byte_size(binary), fn file, bytes ->
            validate_path!(file["path"])

            if file["type"] == "file",
              do: regular_path!(Path.join(entry, "files"), Path.split(file["path"]))

            if file["type"] == "file" and
                 bytes + File.stat!(Path.join([entry, "files", file["path"]])).size >
                   @max_bundle_bytes,
               do: throw(:invalid_entry)

            bytes + restore_file(entry, staging, file)
          end)

        Enum.each(links, &restore_link(staging, build, source, &1))
        if not validate.(staging), do: throw(:invalid_entry)
        swap(staging, build)

        {:ok, duration,
         %{
           read_bytes: bytes,
           read_duration_us: System.monotonic_time(:microsecond) - started,
           read_source: "local"
         }}
      else
        _ -> :miss
      end
    rescue
      _ -> :miss
    catch
      :invalid_entry -> :miss
    after
      File.rm_rf(staging)
    end
  end

  def publish(root, key, build, source, duration) do
    case publish_with_metrics(root, key, build, source, duration) do
      {:ok, _metrics} -> :ok
      error -> error
    end
  end

  def publish_with_metrics(root, key, build, source, duration, validate \\ fn _ -> true end) do
    started = System.monotonic_time(:microsecond)
    entry = Path.join(root, key)
    staging = sibling(entry, "publish")

    try do
      File.mkdir_p!(staging)
      {files, links, _count, _bytes} = snapshot(build, staging, source, "", {[], [], 0, 0})
      if not validate.(Path.join(staging, "files")), do: throw(:invalid_entry)

      manifest =
        JSON.encode!(%{
          version: 1,
          key: key,
          files: files,
          links: links,
          compile_duration_ms: duration
        })

      if byte_size(manifest) > @max_manifest_bytes or
           Enum.reduce(files, byte_size(manifest) + 4, &(&2 + Map.get(&1, :size_bytes, 0))) >
             @max_bundle_bytes,
         do: throw(:invalid_entry)

      File.write!(Path.join(staging, "manifest.json"), manifest)

      result = publish_entry(staging, entry, root, key, source, validate)

      if result == :ok or result in [{:error, :eexist}, {:error, :enotempty}] do
        bytes = Enum.reduce(files, byte_size(manifest), &(&2 + Map.get(&1, :size_bytes, 0)))

        {:ok,
         %{
           write_bytes: bytes,
           write_duration_us: System.monotonic_time(:microsecond) - started,
           write_source: "local"
         }}
      else
        result
      end
    rescue
      error -> {:error, error}
    catch
      :invalid_entry -> {:error, :unsupported_outputs}
    after
      File.rm_rf(staging)
    end
  end

  defp publish_entry(staging, entry, root, key, source, validate) do
    case File.rename(staging, entry) do
      {:error, reason} = error when reason in [:eexist, :enotempty] ->
        check = sibling(entry, "check")

        try do
          case restore_with_metrics(root, key, check, source, validate) do
            {:ok, _, _} ->
              error

            :miss ->
              corrupt = sibling(entry, "corrupt")

              try do
                File.rename(entry, corrupt)
                File.rename(staging, entry)
              after
                File.rm_rf(corrupt)
              end
          end
        after
          File.rm_rf(check)
        end

      result ->
        result
    end
  end

  defp snapshot(build, staging, source, relative, state) do
    build
    |> Path.join(relative)
    |> File.ls!()
    |> Enum.sort()
    |> Enum.reduce(state, fn name, {files, links, count, size} ->
      if count >= @max_files, do: throw(:invalid_entry)
      path = Path.join(relative, name)
      input = Path.join(build, path)

      case File.lstat!(input) do
        %{type: :directory} ->
          File.mkdir_p!(Path.join([staging, "files", path]))

          snapshot(
            build,
            staging,
            source,
            path,
            {[%{path: path, type: "directory"} | files], links, count + 1, size}
          )

        %{type: :regular, mode: mode, size: bytes} ->
          if size + bytes > @max_bundle_bytes, do: throw(:invalid_entry)
          output = Path.join([staging, "files", path])
          File.mkdir_p!(Path.dirname(output))
          File.cp!(input, output)

          bytes = File.read!(output)
          if size + byte_size(bytes) > @max_bundle_bytes, do: throw(:invalid_entry)

          record = %{
            path: path,
            type: "file",
            size_bytes: byte_size(bytes),
            digest: Key.digest(bytes),
            mode: Bitwise.band(mode, 0o777)
          }

          {[record | files], links, count + 1, size + byte_size(bytes)}

        %{type: :symlink} when path in ["priv", "include", "src"] ->
          target = File.read_link!(input) |> Path.expand(Path.dirname(input))
          if target != Path.expand(Path.join(source, path)), do: throw(:invalid_entry)
          {files, [path | links], count + 1, size}

        _ ->
          throw(:invalid_entry)
      end
    end)
  end

  defp restore_file(_entry, staging, %{"path" => path, "type" => "directory"}) do
    validate_path!(path)
    File.mkdir_p!(Path.join(staging, path))
    0
  end

  defp restore_file(entry, staging, %{
         "path" => path,
         "type" => "file",
         "digest" => digest,
         "mode" => mode
       })
       when is_binary(digest) and is_integer(mode) and mode >= 0 and mode <= 0o777 do
    validate_path!(path)
    input = Path.join([entry, "files", path])
    regular_path!(Path.join(entry, "files"), Path.split(path))
    bytes = File.read!(input)
    if Key.digest(bytes) != digest, do: throw(:invalid_entry)
    output = Path.join(staging, path)
    File.mkdir_p!(Path.dirname(output))
    File.write!(output, bytes)
    File.chmod!(output, mode)
    byte_size(bytes)
  end

  defp restore_file(_, _, _), do: throw(:invalid_entry)

  defp restore_link(staging, build, source, name) when name in ["priv", "include", "src"] do
    target_parts = source |> Path.join(name) |> Path.expand() |> Path.split()
    build_parts = build |> Path.expand() |> Path.split()

    shared =
      Enum.zip(target_parts, build_parts) |> Enum.take_while(fn {a, b} -> a == b end) |> length()

    target =
      Path.join(
        List.duplicate("..", length(build_parts) - shared) ++ Enum.drop(target_parts, shared)
      )

    File.ln_s!(target, Path.join(staging, name))
  end

  defp restore_link(_, _, _, _), do: throw(:invalid_entry)

  defp validate_path!(path) when is_binary(path) do
    if path == "" or Path.type(path) != :relative or
         Enum.any?(Path.split(path), &(&1 in ["..", "."])) or String.contains?(path, "\\") do
      throw(:invalid_entry)
    end
  end

  defp validate_path!(_), do: throw(:invalid_entry)

  defp regular_path!(root, [name]) do
    if File.lstat!(Path.join(root, name)).type != :regular, do: throw(:invalid_entry)
  end

  defp regular_path!(root, [name | rest]) do
    next = Path.join(root, name)
    if File.lstat!(next).type != :directory, do: throw(:invalid_entry)
    regular_path!(next, rest)
  end

  # The caller holds Mix's build lock. Keep the old build until the staged
  # replacement is ready, and put it back if the final rename fails.
  defp swap(staging, build) do
    backup = sibling(build, "backup")
    existed? = File.exists?(build)
    if existed?, do: File.rename!(build, backup)

    try do
      File.rename!(staging, build)
    rescue
      error ->
        if existed?, do: File.rename!(backup, build)
        reraise error, __STACKTRACE__
    else
      :ok -> File.rm_rf(backup)
    end
  end

  defp sibling(path, kind),
    do: path <> ".tuist-#{kind}-#{System.pid()}-#{Base.encode16(:crypto.strong_rand_bytes(16))}"
end
