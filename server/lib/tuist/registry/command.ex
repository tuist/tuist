defmodule Tuist.Registry.Command do
  @moduledoc false

  alias Tuist.Registry.Temporary

  def run(command, args, opts \\ []) do
    Temporary.with_directory(fn directory -> run_in(directory, command, args, opts) end)
  end

  defp run_in(directory, command, args, opts) do
    timeout = Keyword.get(opts, :timeout, to_timeout(minute: 5))
    executable = System.find_executable(command) || raise ArgumentError, "registry command unavailable"
    output = Path.join(directory, "output")
    File.touch!(output)

    # MuonTrap's output acknowledgements race quick child exits (:epipe).
    # Redirect to a private file, retaining child/process-group cleanup when
    # the port owner exits. No shared temp-file server is involved.
    task =
      Task.async(fn ->
        System.cmd(
          MuonTrap.muontrap_path(),
          [
            "--delay-to-sigkill",
            "500",
            "--",
            System.find_executable("sh"),
            "-c",
            ~s(output=$1; shift; exec "$@" > "$output" 2>&1),
            "registry-command",
            output,
            executable | args
          ],
          Keyword.delete(opts, :timeout)
        )
      end)

    status =
      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {_, status}} -> status
        nil -> :timeout
      end

    {File.read!(output), status}
  end
end
