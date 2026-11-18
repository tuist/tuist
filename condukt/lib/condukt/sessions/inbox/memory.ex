defmodule Condukt.Sessions.Inbox.Memory do
  @moduledoc """
  A `Condukt.Sessions.Inbox` in the local node's memory, for tests and
  single-node hosts.

  Inputs live in this process, so they are lost with it and seen by this node
  only. Start one under your supervision tree:

      children = [{Condukt.Sessions.Inbox.Memory, name: MyApp.Inbox}]

  and pass it, with the same `:name`, where an inbox is taken:

      config :condukt, inbox: {Condukt.Sessions.Inbox.Memory, name: MyApp.Inbox}

  Options:

    * `:name` - the process name. Defaults to this module.
  """

  @behaviour Condukt.Sessions.Inbox

  use GenServer

  @doc false
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc "Starts the process holding the inputs."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl Condukt.Sessions.Inbox
  def put(input, opts), do: GenServer.call(name(opts), {:put, input})

  @impl Condukt.Sessions.Inbox
  def take(session_id, opts), do: GenServer.call(name(opts), {:take, session_id})

  defp name(opts), do: Keyword.get(opts, :name, __MODULE__)

  # `inputs` holds each session's untaken inputs, newest first. `keys` holds
  # every `{session_id, request_id}` ever put, taken or not.
  @impl GenServer
  def init(:ok), do: {:ok, %{inputs: %{}, keys: MapSet.new()}}

  @impl GenServer
  def handle_call({:put, input}, _from, state) do
    key = {input.session_id, input.request_id}

    if MapSet.member?(state.keys, key) do
      {:reply, {:error, :duplicate}, state}
    else
      inputs = Map.update(state.inputs, input.session_id, [input], &[input | &1])
      {:reply, :ok, %{state | inputs: inputs, keys: MapSet.put(state.keys, key)}}
    end
  end

  def handle_call({:take, session_id}, _from, state) do
    {inputs, rest} = Map.pop(state.inputs, session_id, [])
    {:reply, {:ok, Enum.reverse(inputs)}, %{state | inputs: rest}}
  end
end
