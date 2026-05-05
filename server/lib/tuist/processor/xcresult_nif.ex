defmodule Tuist.Processor.XCResultNIF do
  @moduledoc """
  NIF wrapper for parsing xcresult bundles using Swift.

  The native implementation calls `xcresulttool` and a Swift parser
  compiled as a shared library. Both the .dylib and the C bridge .so
  ship only in the macOS release artifact deployed to the Scaleway
  Mac mini that consumes `:process_xcresult` — Linux pods (web server,
  build-processor) never load this NIF because xcresulttool has no
  Linux equivalent.

  Build the NIF with: `cd server/native/xcresult_nif && ./build.sh`
  (the macOS release pipeline does this as part of the build).
  """

  @on_load :load_nif

  def load_nif do
    nif_path = ~c"#{:code.priv_dir(:tuist)}/native/xcresult_nif"
    nif_so = "#{nif_path}.so"

    case :erlang.load_nif(nif_path, 0) do
      :ok ->
        :ok

      {:error, {:reload, _}} ->
        :ok

      {:error, reason} ->
        # The xcresult NIF is macOS-only by design — `xcresulttool` is
        # part of Xcode and has no Linux equivalent. Linux pods (web
        # server, build-processor) ship without it. Three cases:
        #
        # 1. macOS xcresult-processor pod with the .so present but
        #    broken: refuse to load loudly so the first parse call
        #    raises UndefinedFunctionError instead of silently 5xx-ing
        #    every Oban job.
        # 2. Linux pod or dev/test where the .so is missing: let the
        #    BEAM boot. Linux pods never claim `:process_xcresult` (the
        #    queue isn't started); dev/test exercise the worker via
        #    Mimic stubs, so :nif_not_loaded only fires on direct calls.
        # 3. macOS pod where the .so is missing in a prod build: that's
        #    a packaging bug, fail loud.
        message = "Failed to load xcresult_nif: #{inspect(reason)} (looked at: #{nif_path})"

        cond do
          File.exists?(nif_so) ->
            {:error, message}

          Tuist.Environment.env() in [:dev, :test] ->
            :logger.warning(message <> " — .so missing, skipping (dev/test only)")
            :ok

          :os.type() != {:unix, :darwin} ->
            :ok

          true ->
            {:error, message <> " — .so file missing in a macOS prod build, this is a packaging bug"}
        end
    end
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
