defmodule XcodeProcessor.XCResultNIF do
  @moduledoc """
  NIF wrapper for parsing xcresult bundles using Swift.

  The native implementation uses xcresulttool and Swift parsing logic
  compiled as a shared library loaded via Erlang NIFs.

  Build the NIF with: `cd native/xcresult_nif && swift build -c release`
  """

  @on_load :load_nif

  def load_nif do
    nif_path = ~c"#{:code.priv_dir(:xcode_processor)}/native/xcresult_nif"

    case :erlang.load_nif(nif_path, 0) do
      :ok ->
        :ok

      {:error, {:reload, _}} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to load xcresult NIF from #{nif_path}: #{inspect(reason)}")
        :ok
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

  defp parse_nif(_xcresult_path, _root_directory) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
