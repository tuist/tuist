defmodule Tuist.OpenGraphImages do
  @moduledoc """
  Content-addressed runtime generation and object-storage caching for Open Graph images.
  """

  import Cachex.Spec, only: [expiration: 1, hook: 1]

  alias Tuist.Authentication.SingleFlight
  alias Tuist.Environment
  alias Tuist.Storage

  require Logger

  @actor :open_graph_images
  @storage_prefix "open-graph-images"
  @cache :open_graph_images
  @generation_timeout to_timeout(minute: 2)
  @transient_ttl to_timeout(second: 2)
  @max_transient_entries 128

  def child_spec(opts) do
    SingleFlight.cache_child_spec(__MODULE__, Keyword.get(opts, :cache, @cache),
      expiration: expiration(default: @transient_ttl, interval: @transient_ttl),
      hooks: [hook(module: Cachex.Limit.Scheduled, args: {@max_transient_entries, [], []})]
    )
  end

  def spec(key_parts, params, render) when is_list(key_parts) and is_map(params) and is_function(render, 0) do
    %{key: key(key_parts), params: params, render: render}
  end

  def key(parts) when is_list(parts) do
    parts
    |> Enum.reduce(:crypto.hash_init(:sha256), fn part, acc ->
      :crypto.hash_update(acc, encode_part(part))
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  # Asset digests are stable in a running release, so hashing them once and
  # memoizing keeps every page render from re-digesting fonts, logos and module
  # bytecode. Recompute in dev, where templates and assets hot-reload and a
  # frozen key would keep serving the previously stored image.
  def cached_key(name, parts) when is_atom(name) and is_list(parts) do
    if Environment.dev?() do
      key(parts)
    else
      persistent_key = {__MODULE__, name}

      case :persistent_term.get(persistent_key, nil) do
        nil ->
          key = key(parts)
          :persistent_term.put(persistent_key, key)
          key

        key ->
          key
      end
    end
  end

  def ensure_available(key, resolve, opts \\ []) when is_binary(key) and is_function(resolve, 0) do
    object_key = object_key(key, opts)

    # Published images bypass local coordination, including cache restarts.
    # Cold requests coalesce only on this replica. Other replicas may render
    # equivalent images independently; correctness never depends on membership.
    if Storage.object_exists?(object_key, @actor) do
      :ok
    else
      result =
        SingleFlight.fetch(
          Keyword.get(opts, :cache, @cache),
          {__MODULE__, object_key},
          fn ->
            result =
              if Storage.object_exists?(object_key, @actor) do
                :ok
              else
                generate_and_store(key, object_key, resolve)
              end

            case result do
              {:transient, _image} = transient ->
                {:commit, transient, expire: Keyword.get(opts, :transient_ttl, @transient_ttl)}

              result ->
                {:ignore, result}
            end
          end,
          timeout: Keyword.get(opts, :timeout, @generation_timeout)
        )

      case result do
        {:commit, result} -> result
        {:ignore, result} -> result
        result -> result
      end
    end
  end

  # The image is read fully into memory before the caller commits a response.
  # These are single ~1080p JPEGs, and serving them chunked would mean a
  # mid-download storage failure lands after a 200 with a year-long immutable
  # cache header, freezing a truncated image on CDNs and social platforms under
  # a URL that by construction never changes.
  def fetch(key, opts \\ []) do
    key
    |> object_key(opts)
    |> Storage.get_object(@actor)
  end

  defp generate_and_store(key, object_key, resolve) do
    case resolve.() do
      {:ok, %{key: ^key, render: render}} ->
        case render.() do
          {:ok, image} when is_binary(image) ->
            store(object_key, image)

          # A degraded fallback image is served for this request but not
          # persisted, so a later request can re-render the real image once the
          # underlying failure (e.g. an unavailable browser pool) has cleared.
          {:fallback, image} when is_binary(image) ->
            {:transient, image}

          {:error, _reason} = error ->
            error
        end

      {:ok, %{key: _other_key}} ->
        {:error, :stale_version}

      :error ->
        {:error, :not_found}

      {:error, _reason} = error ->
        error
    end
  end

  # Cache the rendered image and serve it from storage. If the store fails
  # (e.g. a transient object-storage outage) we still hold the rendered bytes,
  # so serve them transiently rather than 503; a later request retries the
  # store once storage recovers.
  defp store(object_key, image) do
    case Storage.put_object(object_key, image, @actor) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to cache Open Graph image #{object_key}, serving it transiently: #{inspect(reason)}")

        {:transient, image}
    end
  end

  defp object_key(key, opts) do
    prefix =
      if Keyword.get(opts, :project, false), do: Path.join(@storage_prefix, "projects"), else: @storage_prefix

    Path.join(prefix, "#{key}.jpg")
  end

  defp encode_part({:file, path}) do
    digest = file_digest(path)
    <<byte_size(digest)::32, digest::binary>>
  end

  defp encode_part({:dir, path}) do
    digest = dir_digest(path)
    <<byte_size(digest)::32, digest::binary>>
  end

  defp encode_part({:module, module}) do
    digest = module_digest(module)
    <<byte_size(digest)::32, digest::binary>>
  end

  defp encode_part(part) when is_binary(part) do
    <<byte_size(part)::32, part::binary>>
  end

  defp encode_part(part), do: encode_part(to_string(part))

  defp file_digest(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        path
        |> File.stream!(65_536)
        |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
        |> :crypto.hash_final()

      _ ->
        :crypto.hash(:sha256, "")
    end
  end

  defp dir_digest(path) do
    path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.reduce(:crypto.hash_init(:sha256), fn file, acc ->
      acc
      |> :crypto.hash_update(Path.relative_to(file, path))
      |> :crypto.hash_update(file_digest(file))
    end)
    |> :crypto.hash_final()
  end

  defp module_digest(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         {^module, binary, _path} <- :code.get_object_code(module) do
      :crypto.hash(:sha256, binary)
    else
      _ -> :crypto.hash(:sha256, Atom.to_string(module))
    end
  end
end
