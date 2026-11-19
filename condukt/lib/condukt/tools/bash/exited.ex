defmodule Condukt.Tools.Bash.Exited do
  @moduledoc """
  The signal that wakes a parked `Condukt.Tools.Bash` call when its command
  ends, under the key `"bash:" <> tool_call_id`.

  The value is the status the watcher saw, as `Condukt.Sandbox.read_process/4`
  reports it, or `{:error, reason}` when the watcher lost the process. The
  woken call reads the status from the sandbox again either way, so a stray
  signal cannot make it report a result the command did not have.
  """

  @behaviour Condukt.Signal

  @impl true
  def cast(:running), do: {:error, :still_running}
  def cast(:timeout), do: {:ok, :timeout}
  def cast({:exited, code} = status) when is_integer(code) or is_nil(code), do: {:ok, status}
  def cast({:error, _reason} = status), do: {:ok, status}
  def cast(_value), do: {:error, :expected_process_status}
end
