defmodule Pulse.Reliability.Worker do
  @moduledoc false
  use Pulse.Runtime.GenServer

  alias Pulse.Reliability
  alias Pulse.Reliability.Repository
  alias Pulse.Reliability.Scope
  alias Pulse.Runtime.GenServer
  alias Pulse.Runtime.ProcessGroup

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    config = Repository.config()
    group = {__MODULE__, config[:endpoint], config[:region], config[:bucket]}
    :ok = ProcessGroup.join(Scope, group, self())
    send(self(), :assess)
    {:ok, %{opts: opts, cursor: 0, group: group, completed: %{}}}
  end

  @impl true
  def handle_info(:assess, state) do
    tenants = Keyword.fetch!(state.opts, :tenants)

    state = if tenants == [], do: state, else: assess(Enum.at(tenants, rem(state.cursor, length(tenants))), state)

    Process.send_after(self(), :assess, Keyword.get(state.opts, :interval_ms, 1000))
    {:noreply, %{state | cursor: state.cursor + 1}}
  end

  defp assess(tenant, state) do
    finish = Reliability.window_end(Repository.now(Reliability.settings()))
    members = ProcessGroup.get_members(Scope, state.group) |> Enum.map(&node/1)

    # This disposable cache only avoids reads. On restart or ownership change,
    # durable CAS claims still authorize every scan and paid attempt.
    if Map.get(state.completed, tenant, -1) < finish and
         Pulse.Rendezvous.owner(["reliability", tenant], members) == node() do
      case Reliability.step(tenant) do
        {:ok, %{"status" => "complete", "window_end_ns" => finish}} ->
          %{state | completed: Map.put(state.completed, tenant, finish)}

        _ ->
          state
      end
    else
      state
    end
  end
end
