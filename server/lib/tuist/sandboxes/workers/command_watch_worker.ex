defmodule Tuist.Sandboxes.Workers.CommandWatchWorker do
  @moduledoc """
  Follows one detached command (`Tuist.Sandboxes.Commands`) until it ends:
  kills it at its deadline, and records how it ended when no client read it,
  which gives the sandbox back once its last command is gone. Snoozes between
  checks; snoozing does not use up attempts.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:command_id], states: [:available, :scheduled], period: :infinity]

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Commands
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.SandboxCommand

  require Logger

  @check_seconds 15
  # A guest that cannot be reached this long after the deadline is not
  # holding a running command anyone can read; give the sandbox back.
  @give_up_after_ms to_timeout(minute: 10)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"sandbox_id" => sandbox_id, "command_id" => id, "deadline_ms" => deadline}}) do
    with %SandboxCommand{status: :running} = command <- Repo.get(SandboxCommand, id),
         %Sandbox{} = sandbox <- Sandboxes.get_sandbox_by_id(sandbox_id) do
      if sandbox.state == :running do
        check(sandbox, command, deadline)
      else
        _ = Commands.record(sandbox, command, :lost, nil)
        :ok
      end
    else
      _ -> :ok
    end
  end

  defp check(sandbox, command, deadline) do
    now = System.system_time(:millisecond)

    case Commands.probe(sandbox, command.id) do
      {:ok, :running, _code} when now >= deadline ->
        _ = Commands.kill(sandbox, command.id, "timeout")
        {:snooze, 5}

      {:ok, :running, _code} ->
        # A release that raced this command's start can drop the macOS host
        # hold after the start took it; holding again is idempotent.
        _ = Sandboxes.hold_host_residency(sandbox, Commands.residency())
        {:snooze, @check_seconds}

      {:ok, status, code} ->
        _ = Commands.record(sandbox, command, status, code)
        :ok

      {:error, :not_found} ->
        _ = Commands.record(sandbox, command, :lost, nil)
        :ok

      {:error, reason} when now >= deadline + @give_up_after_ms ->
        Logger.warning("sandboxes: giving up on an unreachable command", sandbox_id: sandbox.id, reason: inspect(reason))
        _ = Commands.record(sandbox, command, :lost, nil)
        :ok

      {:error, _reason} ->
        {:snooze, @check_seconds}
    end
  end
end
