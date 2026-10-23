defmodule Tuist.OpenGraphImagesTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.OpenGraphImages
  alias Tuist.Storage

  setup do
    cache = String.to_atom("open_graph_images_test_#{System.unique_integer([:positive])}")
    start_supervised!({OpenGraphImages, cache: cache})
    %{cache: cache}
  end

  describe "key/1" do
    test "is deterministic and changes with the rendering attributes" do
      assert OpenGraphImages.key(["page", "English", "Title"]) ==
               OpenGraphImages.key(["page", "English", "Title"])

      refute OpenGraphImages.key(["page", "English", "Title"]) ==
               OpenGraphImages.key(["page", "English", "Different title"])
    end
  end

  describe "spec/3" do
    test "keeps the signed template variables with the render function" do
      params = %{"template" => "marketing", "title" => "About Tuist"}
      render = fn -> {:ok, "image"} end
      spec = OpenGraphImages.spec(["marketing", "About Tuist"], params, render)

      assert spec.params == params
      assert spec.render == render
      assert spec.key == OpenGraphImages.key(["marketing", "About Tuist"])
    end
  end

  test "the application starts the default generation cache before handling cold images" do
    assert is_pid(Process.whereis(:open_graph_images))
    refute :ets.whereis(:open_graph_images_flights) == :undefined
    stub_object_storage()
    key = OpenGraphImages.key(["startup", System.unique_integer([:positive])])
    assert OpenGraphImages.ensure_available(key, successful_render(key)) == :ok
  end

  test "unexpected generation exceptions are reported with a stacktrace and remain uncached", %{cache: cache} do
    stub(Storage, :object_exists?, fn _key, :open_graph_images -> false end)
    reject(&Storage.put_object/3)

    parent = self()

    expect(Sentry, :capture_exception, fn error, opts ->
      send(parent, {:reported_exception, error, opts})
      :ignored
    end)

    log =
      capture_log(fn ->
        assert OpenGraphImages.ensure_available("raised", fn -> raise "unexpected render failure" end, cache: cache) ==
                 {:error, :unavailable}
      end)

    assert log =~ "Unexpected Open Graph image generation failure"
    assert log =~ "RuntimeError"
    assert log =~ "unexpected render failure"
    assert_received {:reported_exception, %RuntimeError{message: "unexpected render failure"}, opts}
    assert [{_, _, _, _} | _] = opts[:stacktrace]
    assert Cachex.get(cache, {OpenGraphImages, "open-graph-images/raised.jpg"}) == nil
  end

  test "a transient image is coalesced locally and retried after eviction", %{cache: cache} do
    parent = self()
    stub(Storage, :object_exists?, fn _key, :open_graph_images -> false end)
    reject(&Storage.put_object/3)

    resolve = fn ->
      {:ok,
       %{
         key: "degraded",
         render: fn ->
           send(parent, :degraded_render)
           {:fallback, "temporary image"}
         end
       }}
    end

    results =
      1..16
      |> Task.async_stream(
        fn _ -> OpenGraphImages.ensure_available("degraded", resolve, cache: cache, transient_ttl: 60_000) end,
        max_concurrency: 16
      )
      |> Enum.to_list()

    assert Enum.all?(results, &(&1 == {:ok, {:transient, "temporary image"}}))
    assert_received :degraded_render
    refute_received :degraded_render
    assert :ok = Cachex.del(cache, {OpenGraphImages, "open-graph-images/degraded.jpg"})
    assert {:transient, "temporary image"} = OpenGraphImages.ensure_available("degraded", resolve, cache: cache)
    assert_received :degraded_render
    assert Cachex.ttl(cache, {OpenGraphImages, "open-graph-images/degraded.jpg"}) in 1..2_000
  end

  test "coalesces same-image generation locally and permits unrelated images", %{cache: cache} do
    stub_object_storage()
    parent = self()
    resolve = blocked_render("same", parent)

    first = Task.async(fn -> OpenGraphImages.ensure_available("same", resolve, cache: cache) end)
    assert_receive {:rendering, "same", renderer}, 5_000
    second = Task.async(fn -> OpenGraphImages.ensure_available("same", resolve, cache: cache) end)
    wait_for_waiter(cache, "open-graph-images/same.jpg", second.pid)

    different =
      Task.async(fn ->
        OpenGraphImages.ensure_available("different", successful_render("different"), cache: cache)
      end)

    assert Task.await(different) == :ok
    assert Task.yield(second, 0) == nil
    refute_received {:rendering, "same", _}
    send(renderer, :finish)
    assert Task.await(first) == :ok
    assert Task.await(second) == :ok
    refute_received {:rendering, "same", _}
    assert Cachex.get(cache, {OpenGraphImages, "open-graph-images/same.jpg"}) == nil
  end

  test "independent replica caches may render the same key concurrently", %{cache: first_cache} do
    second_cache = String.to_atom("open_graph_replica_test_#{System.unique_integer([:positive])}")
    start_supervised!(Supervisor.child_spec({OpenGraphImages, cache: second_cache}, id: second_cache))
    stub_object_storage()
    parent = self()
    resolve = blocked_render("replicated", parent)

    first = Task.async(fn -> OpenGraphImages.ensure_available("replicated", resolve, cache: first_cache) end)
    assert_receive {:rendering, "replicated", first_renderer}, 5_000
    second = Task.async(fn -> OpenGraphImages.ensure_available("replicated", resolve, cache: second_cache) end)
    assert_receive {:rendering, "replicated", second_renderer}, 5_000
    refute first_renderer == second_renderer

    send(first_renderer, :finish)
    send(second_renderer, :finish)
    assert Task.await(first) == :ok
    assert Task.await(second) == :ok
    assert OpenGraphImages.ensure_available("replicated", fn -> flunk("published image") end, cache: first_cache) == :ok
    assert OpenGraphImages.ensure_available("replicated", fn -> flunk("published image") end, cache: second_cache) == :ok
  end

  test "generation does not wait for legacy or per-image Erlang locks", %{cache: cache} do
    key = "no-distribution"
    object_key = "open-graph-images/#{key}.jpg"
    ids = [{OpenGraphImages, self()}, {{OpenGraphImages, object_key}, self()}]
    stub_object_storage()

    Enum.each(ids, fn id -> assert :global.set_lock(id, [node()], 0) end)

    try do
      task = Task.async(fn -> OpenGraphImages.ensure_available(key, successful_render(key), cache: cache) end)
      assert Task.await(task) == :ok
    after
      Enum.each(ids, &:global.del_lock(&1, [node()]))
    end
  end

  test "project and marketing storage prefixes have independent flights", %{cache: cache} do
    stub_object_storage()
    parent = self()

    first =
      Task.async(fn -> OpenGraphImages.ensure_available("prefix", blocked_render("prefix", parent), cache: cache) end)

    assert_receive {:rendering, "prefix", renderer}, 5_000

    second =
      Task.async(fn ->
        OpenGraphImages.ensure_available("prefix", successful_render("prefix"), cache: cache, project: true)
      end)

    assert Task.await(second) == :ok
    send(renderer, :finish)
    assert Task.await(first) == :ok
  end

  test "rechecks shared storage inside a cold flight before rendering", %{cache: cache} do
    checks = :atomics.new(1, [])
    expect(Storage, :object_exists?, 2, fn _key, :open_graph_images -> :atomics.add_get(checks, 1, 1) == 2 end)

    reject(&Storage.put_object/3)
    assert OpenGraphImages.ensure_available("winner", fn -> flunk("another replica published") end, cache: cache) == :ok
  end

  test "a fill timeout cancels its coordinating worker and permits a fresh retry", %{cache: cache} do
    parent = self()
    stub(Storage, :object_exists?, fn _key, :open_graph_images -> false end)
    expect(Storage, :put_object, fn _key, "image", :open_graph_images -> :ok end)

    task =
      Task.async(fn ->
        OpenGraphImages.ensure_available("timeout", blocked_render("timeout", parent), cache: cache, timeout: 1_000)
      end)

    assert_receive {:rendering, "timeout", renderer}, 5_000
    ref = Process.monitor(renderer)
    assert Task.await(task) == {:error, :unavailable}
    assert_receive {:DOWN, ^ref, :process, ^renderer, :killed}, 5_000
    assert Cachex.get(cache, {OpenGraphImages, "open-graph-images/timeout.jpg"}) == nil
    assert OpenGraphImages.ensure_available("timeout", successful_render("timeout"), cache: cache) == :ok
  end

  test "a short-lived waiter cannot cancel another request's healthy render", %{cache: cache} do
    stub_object_storage()
    parent = self()
    resolve = blocked_render("waiter", parent)
    initiator = Task.async(fn -> OpenGraphImages.ensure_available("waiter", resolve, cache: cache) end)
    assert_receive {:rendering, "waiter", renderer}, 5_000

    assert OpenGraphImages.ensure_available("waiter", fn -> flunk("duplicate render") end, cache: cache, timeout: 50) ==
             {:error, :unavailable}

    assert Process.alive?(renderer)
    send(renderer, :finish)
    assert Task.await(initiator) == :ok
  end

  test "render errors and invalid specifications are not retained", %{cache: cache} do
    stub(Storage, :object_exists?, fn _key, :open_graph_images -> false end)
    expect(Storage, :put_object, fn _key, "image", :open_graph_images -> :ok end)

    assert OpenGraphImages.ensure_available("retry", fn -> {:error, :failed} end, cache: cache) == {:error, :failed}
    assert OpenGraphImages.ensure_available("retry", fn -> :error end, cache: cache) == {:error, :not_found}

    assert OpenGraphImages.ensure_available("retry", fn -> {:ok, %{key: "different"}} end, cache: cache) ==
             {:error, :stale_version}

    assert Cachex.get(cache, {OpenGraphImages, "open-graph-images/retry.jpg"}) == nil
    assert OpenGraphImages.ensure_available("retry", successful_render("retry"), cache: cache) == :ok
  end

  test "storage write failures are transient and recovery bypasses the degraded cache", %{cache: cache} do
    expect(Storage, :object_exists?, 2, fn _key, :open_graph_images -> false end)
    expect(Storage, :put_object, fn _key, "image", :open_graph_images -> {:error, :storage_down} end)

    assert OpenGraphImages.ensure_available("recovery", successful_render("recovery"), cache: cache) ==
             {:transient, "image"}

    assert Cachex.get(cache, {OpenGraphImages, "open-graph-images/recovery.jpg"}) == {:transient, "image"}

    expect(Storage, :object_exists?, fn _key, :open_graph_images -> true end)
    assert OpenGraphImages.ensure_available("recovery", fn -> flunk("published image") end, cache: cache) == :ok
  end

  test "an unavailable local cache rejects cold work but still serves published images" do
    expect(Storage, :object_exists?, fn _key, :open_graph_images -> false end)
    reject(&Storage.put_object/3)

    assert OpenGraphImages.ensure_available("cold", fn -> flunk("uncoordinated render") end,
             cache: :absent_open_graph_cache
           ) ==
             {:error, :unavailable}

    expect(Storage, :object_exists?, fn _key, :open_graph_images -> true end)

    assert OpenGraphImages.ensure_available("warm", fn -> flunk("published image") end, cache: :absent_open_graph_cache) ==
             :ok
  end

  defp blocked_render(key, parent) do
    fn ->
      {:ok,
       %{
         key: key,
         render: fn ->
           send(parent, {:rendering, key, self()})

           receive do
             :finish -> {:ok, "image"}
           end
         end
       }}
    end
  end

  defp successful_render(key), do: fn -> {:ok, %{key: key, render: fn -> {:ok, "image"} end}} end

  defp stub_object_storage do
    objects = start_supervised!({Agent, fn -> MapSet.new() end})
    stub(Storage, :object_exists?, fn key, :open_graph_images -> Agent.get(objects, &MapSet.member?(&1, key)) end)
    stub(Storage, :put_object, fn key, _image, :open_graph_images -> Agent.update(objects, &MapSet.put(&1, key)) end)
  end

  defp wait_for_waiter(cache, object_key, waiter) do
    wait_for_waiter(cache, object_key, waiter, System.monotonic_time(:millisecond) + 5_000)
  end

  defp wait_for_waiter(cache, object_key, waiter, deadline) do
    table = String.to_existing_atom("#{cache}_flights")
    [{_, coordinator}] = :ets.lookup(table, {OpenGraphImages, object_key})
    {:monitored_by, monitors} = Process.info(coordinator, :monitored_by)

    cond do
      waiter in monitors ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("waiter did not join the local flight")

      true ->
        Process.sleep(1)
        wait_for_waiter(cache, object_key, waiter, deadline)
    end
  end
end
