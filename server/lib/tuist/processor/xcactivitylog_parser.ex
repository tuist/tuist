defmodule Tuist.Processor.XCActivityLogParser do
  @moduledoc """
  Parses xcactivitylog files by running the Swift `xcactivitylog-parser`
  executable that ships in the release's `priv/native`.

  The parse runs in its own OS process. Swift aborts the process on a runtime
  trap — an out-of-range integer conversion on a malformed log, say — and there
  is no way to catch that from the calling code. In-process, that killed the
  BEAM and every job the pod had in flight; out of process it costs the one job
  and comes back as `{:error, {:parser_crashed, status, output}}`.

  Build the executable with: `cd server/native/xcactivitylog_nif && ./build.sh`
  (the server Dockerfile does this as part of the image build).
  """

  @executable "xcactivitylog-parser"

  # Below `ProcessBuildWorker`'s 5 minute wall-time limit so a wedged parse
  # returns a structured error before Oban kills the job.
  @timeout to_timeout(minute: 4)
  @delay_to_sigkill to_timeout(second: 5)

  @doc """
  Parses an xcactivitylog file and returns structured build data.

  ## Parameters

    * `xcactivitylog_path` - Path to the .xcactivitylog file
    * `cas_analytics_db_path` - Path to the CAS analytics SQLite database
    * `legacy_cas_metadata_path` - Path to the legacy CAS metadata directory (for backward compatibility)
    * `xcode_cache_upload_enabled` - Accepted for call-site compatibility; the parser does not read it

  ## Returns

    * `{:ok, map}` - Parsed build data as a map
    * `{:error, reason}` - If parsing fails
  """
  def parse(xcactivitylog_path, cas_analytics_db_path, legacy_cas_metadata_path, _xcode_cache_upload_enabled) do
    output_path = Path.join(System.tmp_dir!(), "xcactivitylog_#{System.unique_integer([:positive])}.json")

    try do
      with {:ok, executable} <- executable_path(),
           :ok <-
             run(executable, [
               xcactivitylog_path,
               cas_analytics_db_path,
               legacy_cas_metadata_path,
               output_path
             ]),
           {:ok, json} <- File.read(output_path) do
        JSON.decode(json)
      end
    after
      File.rm(output_path)
    end
  end

  defp run(executable, arguments) do
    case MuonTrap.cmd(executable, arguments,
           timeout: @timeout,
           delay_to_sigkill: @delay_to_sigkill,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      {_output, :timeout} ->
        {:error, :parse_timeout}

      # muontrap reports a child killed by a signal as 128 + signum, so a Swift
      # trap (SIGILL) arrives here as 132. Keep it distinguishable from an
      # error the parser reported itself: a crash means a build we cannot parse
      # until the trap is fixed, not a transient failure worth retrying.
      {output, status} when status > 128 ->
        {:error, {:parser_crashed, status, String.trim(output)}}

      {output, _status} ->
        {:error, String.trim(output)}
    end
  end

  defp executable_path do
    path = Path.join([:code.priv_dir(:tuist), "native", @executable])

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, {:parser_not_found, path}}
    end
  end
end
