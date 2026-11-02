defmodule Tuist.ContentCacheTest do
  use ExUnit.Case, async: true

  alias Tuist.ContentCache
  alias Tuist.ContentCache.LoadError

  setup do
    {:ok, cache: start_cache()}
  end

  test "caches loaded values", %{cache: cache} do
    loads = :counters.new(1, [:atomics])

    loader = fn ->
      :counters.add(loads, 1, 1)
      "value"
    end

    assert ContentCache.get(cache, :key, loader) == "value"
    assert ContentCache.get(cache, :key, loader) == "value"
    assert :counters.get(loads, 1) == 1
  end

  test "caches nil values", %{cache: cache} do
    loads = :counters.new(1, [:atomics])

    loader = fn ->
      :counters.add(loads, 1, 1)
      nil
    end

    assert ContentCache.get(cache, :missing, loader) == nil
    assert ContentCache.get(cache, :missing, loader) == nil
    assert :counters.get(loads, 1) == 1
  end

  test "shares an in-progress load for the same key", %{cache: cache} do
    test_process = self()

    loader = fn ->
      send(test_process, {:loader_started, self()})

      receive do
        :continue -> "value"
      end
    end

    first = Task.async(fn -> ContentCache.get(cache, :key, loader) end)
    assert_receive {:loader_started, loader_process}

    second = Task.async(fn -> ContentCache.get(cache, :key, loader) end)
    refute_receive {:loader_started, _}, 100

    send(loader_process, :continue)

    assert Task.await(first) == "value"
    assert Task.await(second) == "value"
  end

  test "loads different keys concurrently", %{cache: cache} do
    test_process = self()

    blocked =
      Task.async(fn ->
        ContentCache.get(cache, :blocked, fn ->
          send(test_process, {:blocked_loader_started, self()})

          receive do
            :continue -> "blocked"
          end
        end)
      end)

    assert_receive {:blocked_loader_started, blocked_loader}

    assert ContentCache.get(cache, :independent, fn -> "independent" end) == "independent"

    send(blocked_loader, :continue)
    assert Task.await(blocked) == "blocked"
  end

  test "bounds concurrent loads for different keys" do
    cache = start_cache(max_concurrency: 2)
    test_process = self()

    tasks =
      Enum.map(1..3, fn index ->
        Task.async(fn ->
          ContentCache.get(cache, index, fn ->
            send(test_process, {:loader_started, index, self()})

            receive do
              :continue -> index
            end
          end)
        end)
      end)

    started =
      Enum.map(1..2, fn _ ->
        assert_receive {:loader_started, index, loader}
        {index, loader}
      end)

    refute_receive {:loader_started, _, _}, 100

    {_index, first_loader} = List.first(started)
    send(first_loader, :continue)
    assert_receive {:loader_started, _index, third_loader}

    started
    |> Enum.drop(1)
    |> Enum.each(fn {_index, loader} -> send(loader, :continue) end)

    send(third_loader, :continue)

    assert tasks |> Task.await_many() |> Enum.sort() == [1, 2, 3]
  end

  test "clears values without eagerly reloading them", %{cache: cache} do
    loads = :counters.new(1, [:atomics])

    loader = fn ->
      :counters.add(loads, 1, 1)
      :counters.get(loads, 1)
    end

    assert ContentCache.get(cache, :key, loader) == 1
    assert ContentCache.reload(cache) == :ok
    assert :counters.get(loads, 1) == 1
    assert ContentCache.get(cache, :key, loader) == 2
  end

  test "restarts in-progress loads when clearing the cache", %{cache: cache} do
    test_process = self()
    loads = :counters.new(1, [:atomics])

    loader = fn ->
      :counters.add(loads, 1, 1)
      load = :counters.get(loads, 1)
      send(test_process, {:loader_started, load, self()})

      receive do
        :continue -> load
      end
    end

    task = Task.async(fn -> ContentCache.get(cache, :key, loader) end)
    assert_receive {:loader_started, 1, first_loader}
    first_loader_monitor = Process.monitor(first_loader)

    assert ContentCache.reload(cache) == :ok
    assert_receive {:loader_started, 2, second_loader}
    assert_receive {:DOWN, ^first_loader_monitor, :process, ^first_loader, :killed}

    send(second_loader, :continue)

    assert Task.await(task) == 2
    assert ContentCache.get(cache, :key, loader) == 2
    assert :counters.get(loads, 1) == 2
  end

  test "times out a load and releases its key" do
    cache = start_cache(load_timeout: 25)

    assert_raise LoadError, "Content cache load timed out", fn ->
      ContentCache.get(cache, :key, fn -> Process.sleep(:infinity) end)
    end

    assert ContentCache.get(cache, :key, fn -> "recovered" end) == "recovered"
  end

  test "preserves loader exceptions", %{cache: cache} do
    assert_raise RuntimeError, "loading failed", fn ->
      ContentCache.get(cache, :key, fn -> raise "loading failed" end)
    end
  end

  test "loads directly when the cache is not running" do
    assert ContentCache.get(:missing_content_cache, :key, fn -> "value" end) == "value"
  end

  @tag :tmp_dir
  test "compile-time loaders wait for modules that are still compiling", %{cache: cache, tmp_dir: tmp_dir} do
    id = System.unique_integer([:positive])
    caller = Module.concat(__MODULE__, "CompileTimeCaller#{id}")
    dependency = Module.concat(__MODULE__, "CompilingDependency#{id}")
    test_process = :"#{__MODULE__}.Process#{id}"
    Process.register(self(), test_process)

    caller_path = Path.join(tmp_dir, "caller.ex")
    dependency_path = Path.join(tmp_dir, "dependency.ex")

    File.write!(caller_path, """
    defmodule #{inspect(caller)} do
      @value Tuist.ContentCache.get(#{inspect(cache)}, :key, fn ->
               send(#{inspect(test_process)}, :loader_started)
               #{inspect(dependency)}.value()
             end)

      def value, do: @value
    end
    """)

    File.write!(dependency_path, """
    defmodule #{inspect(dependency)} do
      send(#{inspect(test_process)}, {:dependency_compiling, self()})

      receive do
        :continue -> :ok
      end

      def value, do: "value"
    end
    """)

    on_exit(fn ->
      for module <- [caller, dependency] do
        :code.purge(module)
        :code.delete(module)
      end
    end)

    compilation =
      Task.async(fn ->
        Kernel.ParallelCompiler.compile([caller_path, dependency_path], return_diagnostics: true)
      end)

    assert_receive :loader_started
    assert_receive {:dependency_compiling, dependency_compiler}
    send(dependency_compiler, :continue)

    assert {:ok, modules, _diagnostics} = Task.await(compilation)
    assert Enum.sort(modules) == Enum.sort([caller, dependency])
    assert caller.value() == "value"
  end

  defp start_cache(opts \\ []) do
    cache = String.to_atom("content_cache_#{System.unique_integer([:positive])}")
    start_supervised!({ContentCache, Keyword.put(opts, :name, cache)})
    cache
  end
end
