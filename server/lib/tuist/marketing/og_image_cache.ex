defmodule Tuist.Marketing.OgImageCache do
  @moduledoc """
  Sidecar cache for OG image generation. Each rendered image is paired with a
  `<image>.cachekey` file holding a SHA-256 of the inputs that produced it.
  Subsequent runs that compute the same key skip the (slow) Chromium /
  libvips render entirely.

  The cache pairs with a BuildKit `--mount=type=cache` on the output
  directory in the Docker build, so the JPEG + cache key sidecars persist
  across image builds. When inputs are unchanged, the og generation step
  becomes a fast no-op even when `mix compile` upstream had to rerun.

  ## Cache key parts

  `key/1` accepts a list of parts; each part can be:

    * a binary (e.g. title, locale) — length-prefixed and embedded directly
    * `{:file, path}` — hashed by content
    * `{:dir, path}`  — hashed by sorted-recursive file content

  Parts are concatenated with length prefixes so that `[\"ab\", \"c\"]` and
  `[\"a\", \"bc\"]` hash differently.
  """

  @suffix ".cachekey"

  def key(parts) when is_list(parts) do
    parts
    |> Enum.reduce(:crypto.hash_init(:sha256), fn part, acc ->
      :crypto.hash_update(acc, encode_part(part))
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  def hit?(image_path, expected_key) do
    case File.read(image_path <> @suffix) do
      {:ok, ^expected_key} -> File.regular?(image_path)
      _ -> false
    end
  end

  def put(image_path, key) do
    File.write!(image_path <> @suffix, key)
  end

  defp encode_part(part) when is_binary(part) do
    <<byte_size(part)::32, part::binary>>
  end

  defp encode_part({:file, path}) do
    digest = file_digest(path)
    <<byte_size(digest)::32, digest::binary>>
  end

  defp encode_part({:dir, path}) do
    digest = dir_digest(path)
    <<byte_size(digest)::32, digest::binary>>
  end

  defp file_digest(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        path
        |> File.stream!(65_536)
        |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
        |> :crypto.hash_final()

      _ ->
        # Treat missing files as a fixed empty digest so the cache key still
        # changes if the file later appears.
        :crypto.hash(:sha256, "")
    end
  end

  defp dir_digest(path) do
    files =
      path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    Enum.reduce(files, :crypto.hash_init(:sha256), fn file, acc ->
      acc
      |> :crypto.hash_update(file)
      |> :crypto.hash_update(file_digest(file))
    end)
    |> :crypto.hash_final()
  end
end
