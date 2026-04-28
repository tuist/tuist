defmodule Tuist.Processor.XCActivityLogNIF do
  @moduledoc """
  NIF wrapper for parsing xcactivitylog files using Swift.

  The native implementation depends on the TuistXCActivityLog Swift package
  and is compiled as a shared library loaded via Erlang NIFs.

  Build the NIF with: `cd server/native/xcactivitylog_nif && ./build.sh`
  (the server Dockerfile does this as part of the image build).
  """

  @on_load :load_nif

  def load_nif do
    nif_path = ~c"#{:code.priv_dir(:tuist)}/native/xcactivitylog_nif"
    nif_so = "#{nif_path}.so"

    case :erlang.load_nif(nif_path, 0) do
      :ok ->
        :ok

      {:error, {:reload, _}} ->
        :ok

      {:error, reason} ->
        # All shipped Docker images include the NIF (the Dockerfile builds
        # it as part of every release). If the .so file is present but the
        # load failed, that's a real packaging/ABI bug — refuse to start so
        # the failure is loud (CrashLoopBackOff) instead of silently
        # 5xx-ing every parse job. If the file is missing, we're in a dev
        # checkout where `cd server/native/xcactivitylog_nif && ./build.sh`
        # hasn't been run; let the BEAM boot so the rest of the app stays
        # usable, and fail at parse time with `:nif_not_loaded`.
        message = "Failed to load xcactivitylog_nif: #{inspect(reason)} (looked at: #{nif_path})"

        if File.exists?(nif_so) do
          {:error, message}
        else
          :logger.warning(message <> " — file missing, skipping (dev/test only)")
          :ok
        end
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
  def parse(xcactivitylog_path, cas_analytics_db_path, legacy_cas_metadata_path, xcode_cache_upload_enabled) do
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

  defp parse_nif(_xcactivitylog_path, _cas_analytics_db_path, _legacy_cas_metadata_path, _xcode_cache_upload_enabled) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
