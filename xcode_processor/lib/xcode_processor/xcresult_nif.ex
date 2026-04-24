defmodule XcodeProcessor.XCResultNIF do
  @moduledoc """
  NIF wrapper for parsing xcresult bundles using Swift.

  The native implementation uses xcresulttool and Swift parsing logic
  compiled as a shared library loaded via Erlang NIFs.

  Build the NIF with: `cd native/xcresult_nif && swift build -c release`
  """

  @on_load :load_nif

  @nif_loaded :nif_load_status

  def load_nif do
    nif_path = ~c"#{:code.priv_dir(:xcode_processor)}/native/xcresult_nif"

    case :erlang.load_nif(nif_path, 0) do
      :ok ->
        :persistent_term.put(@nif_loaded, true)
        :ok

      {:error, {:reload, _}} ->
        :persistent_term.put(@nif_loaded, true)
        :ok

      {:error, _reason} ->
        :persistent_term.put(@nif_loaded, false)
        :ok
    end
  end

  def nif_loaded? do
    :persistent_term.get(@nif_loaded, false)
  end

  @doc """
  Parses an xcresult bundle and returns structured test data.

  ## Parameters

    * `xcresult_path` - Path to the .xcresult bundle
    * `root_directory` - Root directory for computing relative paths

  ## Returns

    * `{:ok, map}` - Parsed test data as a map
    * `{:error, reason}` - If parsing fails
  """
  def parse(xcresult_path, root_directory) do
    case parse_nif(xcresult_path, root_directory) do
      {:ok, json_binary} ->
        JSON.decode(json_binary)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Extracts an AppleArchive (.aar) payload into `destination_dir` using the
  native Apple Archive framework. PKZIP archives are not handled here — the
  caller should dispatch on magic bytes first.
  """
  def decompress_archive(source_path, destination_dir) do
    decompress_archive_nif(source_path, destination_dir)
  end

  defp parse_nif(_xcresult_path, _root_directory) do
    :erlang.nif_error(:nif_not_loaded)
  end

  defp decompress_archive_nif(_source_path, _destination_dir) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
