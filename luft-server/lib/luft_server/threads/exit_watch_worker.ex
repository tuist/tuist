defmodule LuftServer.Threads.ExitWatchWorker do
  @moduledoc """
  Durable parked-process completion delivery hosted by Luft's agent runner.
  The encrypted watch and its wanted lease commit together in PostgreSQL.
  A replacement park replaces the signal key; delivery rereads it. Repeated
  delivery is safe because Condukt consumes a signal key once. No Oban needed.
  Register `"thread_exit_watch" => __MODULE__` in Agents.Runner's kinds.
  """
  @behaviour LuftServer.Agents.Kind

  use GenServer

  alias LuftServer.Agents.Kind
  alias LuftServer.Agents.Lease
  alias LuftServer.Repo
  alias LuftServer.Threads.Capabilities
  alias LuftServer.Threads.EncryptedBinary
  alias LuftServer.Threads.Sandbox

  def enqueue(args) do
    id = "thread-exit-watch:" <> args.command_id
    {:ok, body} = args |> Jason.encode!() |> EncryptedBinary.dump()

    with {:ok, :ok} <-
           Repo.transaction(fn ->
             Repo.query!(
               "INSERT INTO agent_objects (key, body) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET body=EXCLUDED.body",
               [id, body],
               log: false
             )

             Lease.want(id, "thread_exit_watch")
           end) do
      Lease.wake(id)
      :ok
    end
  end

  @impl Kind
  def start(id, epoch), do: GenServer.start(__MODULE__, {id, epoch})
  @impl Kind
  def stop_if_idle(pid, reply_to, token),
    do: GenServer.cast(pid, {:stop_if_idle, reply_to, token})

  @impl Kind
  def drain(pid), do: GenServer.cast(pid, :drain)

  @impl true
  def init({id, epoch}) do
    send(self(), :poll)
    {:ok, %{id: id, epoch: epoch, task: nil, done: false}}
  end

  @impl true
  def handle_cast({:stop_if_idle, reply_to, token}, %{done: true} = state) do
    send(reply_to, {Kind, :idle, self(), token})
    {:stop, :normal, state}
  end

  def handle_cast({:stop_if_idle, _, _}, state), do: {:noreply, state}

  def handle_cast(:drain, state) do
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
    {:stop, {:shutdown, :drain}, state}
  end

  @impl true
  def handle_info(:poll, %{task: nil} = state) do
    id = state.id
    task = Task.Supervisor.async_nolink(LuftServer.Threads.Tasks, fn -> poll(id) end)
    {:noreply, %{state | task: task}}
  end

  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    done = finish(state, result)
    if !done, do: Process.send_after(self(), :poll, 1_000)
    {:noreply, %{state | task: nil, done: done}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{task: %Task{ref: ref}} = state) do
    Process.send_after(self(), :poll, 15_000)
    {:noreply, %{state | task: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp poll(id) do
    case load(id) do
      {:ok, args, body} ->
        case poll_args(args) do
          :retry -> :retry
          result -> {:complete, body, result}
        end

      :not_found ->
        :missing

      _ ->
        :retry
    end
  end

  defp poll_args(args) do
    with {:ok, owner} <- owner(args["owner"]),
         {:ok, sandbox} <- Capabilities.sandbox(owner, "show", %{sandbox_id: args["sandbox_id"]}),
         true <- sandbox.account_id == args["account_id"],
         {:ok, read} <-
           Capabilities.command(sandbox, "command_watch", args["command_id"], %{wait_seconds: 25}) do
      case Sandbox.status(read) do
        :running -> :retry
        status -> {:deliver, status}
      end
    else
      {:error, :delegation_unavailable} -> :discard
      {:error, :not_found} -> {:deliver, {:error, :not_found}}
      _ -> :retry
    end
  end

  defp finish(_state, :retry), do: false
  defp finish(state, :missing), do: load(state.id) == :not_found

  defp finish(state, {:complete, expected_body, result}) do
    # Only this lease epoch may consume the current watch. A new enqueue
    # changes both body and want_seq; an old completion cannot erase it.
    with {:ok, args, ^expected_body} <- load(state.id),
         %{rows: [[true]]} <-
           Repo.query!(
             "SELECT EXISTS(SELECT 1 FROM agent_sessions WHERE id=$1 AND epoch=$2 AND lease_expires_at > CURRENT_TIMESTAMP)",
             [state.id, state.epoch],
             log: false
           ),
         :ok <- deliver(args, result) do
      %{num_rows: count} =
        Repo.query!(
          "DELETE FROM agent_objects WHERE key=$1 AND body=$2",
          [state.id, expected_body],
          log: false
        )

      count == 1
    else
      :not_found -> true
      _ -> false
    end
  end

  defp deliver(_args, :discard), do: :ok

  defp deliver(args, {:deliver, status}) do
    with {:ok, signal} <- signal(args["signal"]) do
      case Condukt.signal(args["session_id"], signal, args["key"], status) do
        :ok -> :ok
        {:error, reason} when reason in [:duplicate, :closed] -> :ok
        error -> error
      end
    end
  end

  defp load(id) do
    case Repo.query!("SELECT body FROM agent_objects WHERE key=$1", [id], log: false).rows do
      [[body]] ->
        with {:ok, json} <- EncryptedBinary.load(body),
             {:ok, args} <- Jason.decode(json),
             do: {:ok, args, body}

      [] ->
        :not_found
    end
  end

  defp owner(%{
         "owner_session_id" => session,
         "owner_id" => user,
         "account_id" => account,
         "account_handle" => handle
       }),
       do:
         {:ok,
          %{
            owner_session_id: session,
            owner_id: user,
            account_id: account,
            account_handle: handle
          }}

  defp owner(_), do: :error

  defp signal(name) when is_binary(name) do
    module = String.to_existing_atom(name)

    if Code.ensure_loaded?(module) and function_exported?(module, :cast, 1),
      do: {:ok, module},
      else: :error
  rescue
    ArgumentError -> :error
  end

  defp signal(_), do: :error
end
