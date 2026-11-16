defmodule Condukt.Sessions.RegistryTest do
  use ExUnit.Case, async: true

  alias Condukt.Sessions.Registry.Horde
  alias Condukt.Sessions.Registry.Local
  alias Condukt.Sessions.Registry.PG
  alias Condukt.Test.LLMProvider

  defmodule Idle do
    use GenServer

    def start_link(name), do: GenServer.start_link(__MODULE__, :ok, name: name)

    @impl true
    def init(:ok), do: {:ok, :ok}

    @impl true
    def handle_call(:ping, _from, state), do: {:reply, :pong, state}
  end

  defmodule Agent do
    use Condukt

    @impl true
    def init(_opts), do: {:ok, :ok}
  end

  defmodule Answer do
    @behaviour Condukt.Signal

    @impl true
    def cast(value), do: {:ok, value}
  end

  # Each adapter runs on its own instance, named per test, so the tests stay
  # async and leave the application's registry alone.
  for {registry, key} <- [{Local, :name}, {PG, :scope}, {Horde, :name}] do
    describe inspect(registry) do
      @describetag registry: registry, key: key

      setup %{registry: registry, key: key} do
        opts = [{key, :"registry_test_#{System.unique_integer([:positive])}"}]
        start_supervised!(registry.child_spec(opts))
        %{opts: opts}
      end

      test "names a process by id, refuses a second one, and forgets it when it exits", %{
        registry: registry,
        opts: opts
      } do
        {:ok, pid} = Idle.start_link(registry.via("session-1", opts))

        await(fn -> registry.whereis("session-1", opts) == pid end)
        assert registry.list(opts) == ["session-1"]
        assert GenServer.call(registry.via("session-1", opts), :ping) == :pong
        assert Idle.start_link(registry.via("session-1", opts)) == {:error, {:already_started, pid}}

        GenServer.stop(pid)
        # Cluster registries forget a session eventually, not as it exits.
        await(fn -> registry.whereis("session-1", opts) == nil and registry.list(opts) == [] end)
      end

      test "a process started under the id of one that just stopped is registered", %{
        registry: registry,
        opts: opts
      } do
        for _attempt <- 1..200 do
          {:ok, pid} = Idle.start_link(registry.via("restart", opts))
          GenServer.stop(pid)
        end
      end

      test "records children from their own processes, apart from ids, until they exit", %{
        registry: registry,
        opts: opts
      } do
        {:ok, parent} = Idle.start_link(registry.via("parent", opts))
        test = self()

        children =
          for _child <- 1..2 do
            spawn(fn ->
              :ok = registry.join_parent("parent", opts)
              send(test, :joined)
              receive do: (:exit -> :ok)
            end)
          end

        assert_receive :joined
        assert_receive :joined
        await(fn -> Enum.sort(registry.children("parent", opts)) == Enum.sort(children) end)
        assert registry.list(opts) == ["parent"]
        assert registry.children("other", opts) == []

        Enum.each(children, &send(&1, :exit))
        await(fn -> registry.children("parent", opts) == [] end)
        assert registry.whereis("parent", opts) == parent
      end

      test "signals reach a session named through the adapter, and a missing name is not found", %{
        registry: registry,
        opts: opts
      } do
        {model, _id} = LLMProvider.model([])
        name = registry.via("agent", opts)

        start_supervised!({Agent, model: model, name: name, load_project_instructions: false})

        # Reached, and idle, so the key is closed rather than unknown.
        assert Condukt.signal(name, Answer, "k", %{"text" => "hi"}) == {:error, :closed}
        assert Condukt.signal(registry.via("missing", opts), Answer, "k", %{"text" => "hi"}) == {:error, :not_found}
      end
    end
  end

  defp await(fun, attempts \\ 100) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition never held")
      true -> Process.sleep(5) && await(fun, attempts - 1)
    end
  end
end
