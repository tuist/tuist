defmodule Processor.XCActivityLogNIF do
  @moduledoc """
  NIF wrapper for parsing xcactivitylog files using Swift.

  The native implementation depends on the XCLogParser Swift package
  and is compiled as a shared library loaded via Erlang NIFs.

  Build the NIF with: `cd native/xcactivitylog_nif && ./build.sh`
  """

  @on_load :load_nif

  def load_nif do
    nif_path = ~c"#{:code.priv_dir(:processor)}/native/xcactivitylog_nif"

    case :erlang.load_nif(nif_path, 0) do
      :ok -> :ok
      {:error, {:reload, _}} -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc """
  Parses an xcactivitylog file and returns structured build data.

  ## Parameters

    * `xcactivitylog_path` - Path to the .xcactivitylog file
    * `cas_analytics_db_path` - Path to the CAS analytics SQLite database
    * `legacy_cas_metadata_path` - Path to the legacy CAS metadata directory (for backward compatibility)
    * `xcode_cache_upload_enabled` - Whether cache upload was enabled for this build

  ## Returns

    * `{:ok, map}` - Parsed build data as a map
    * `{:error, reason}` - If parsing fails
  """
  def parse(
        xcactivitylog_path,
        cas_analytics_db_path,
        legacy_cas_metadata_path,
        xcode_cache_upload_enabled
      ) do
    case parse_nif(
           xcactivitylog_path,
           cas_analytics_db_path,
           legacy_cas_metadata_path,
           xcode_cache_upload_enabled
         ) do
      {:ok, json_binary} ->
        JSON.decode(json_binary)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_nif(
         _xcactivitylog_path,
         _cas_analytics_db_path,
         _legacy_cas_metadata_path,
         _xcode_cache_upload_enabled
       ) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
