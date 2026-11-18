defmodule Condukt.SessionStore.ObjectStoreTest do
  use ExUnit.Case, async: true
  use Condukt.SessionStore.Conformance, store: Condukt.SessionStore.ObjectStore

  alias Condukt.Message
  alias Condukt.SessionStore.ObjectStore
  alias Condukt.SessionStore.ObjectStore.Memory
  alias Condukt.SessionStore.Snapshot

  # Runs a function before each create, so a test can act as another writer
  # at exactly that moment.
  defmodule HookedBucket do
    @behaviour Condukt.SessionStore.ObjectStore.Bucket

    alias Condukt.SessionStore.ObjectStore.Memory

    @impl true
    def create({memory, hook}, key, body) do
      hook.(key)
      Memory.create(memory, key, body)
    end

    @impl true
    def get({memory, _hook}, key), do: Memory.get(memory, key)
    @impl true
    def list({memory, _hook}, prefix, start_after), do: Memory.list(memory, prefix, start_after)
    @impl true
    def delete({memory, _hook}, key), do: Memory.delete(memory, key)
  end

  setup do
    {:ok, memory} = Memory.start_link()
    bucket = {Memory, memory}
    %{memory: memory, store_opts: [bucket: bucket, key: "a"], other_store_opts: [bucket: bucket, key: "b"]}
  end

  describe "fencing" do
    test "a newer epoch refuses the older writer's appends and saves", %{store_opts: opts} do
      old = Keyword.put(opts, :epoch, 1)
      new = Keyword.put(opts, :epoch, 2)

      assert :ok = ObjectStore.append_journal([{:resume, 1, nil}], old)
      assert ObjectStore.load_journal(new) == {:ok, [{:resume, 1, nil}]}

      assert ObjectStore.append_journal([{:resume, 2, nil}], old) == {:error, :fenced}
      assert ObjectStore.save(Snapshot.new(%{messages: [Message.user("stale")]}), old) == {:error, :fenced}
      assert ObjectStore.clear_journal(old) == {:error, :fenced}
      assert ObjectStore.load(old) == {:error, :fenced}

      assert :ok = ObjectStore.append_journal([{:resume, 3, nil}], new)
      assert ObjectStore.load_journal(new) == {:ok, [{:resume, 1, nil}, {:resume, 3, nil}]}
      assert ObjectStore.load(new) == :not_found
    end

    # The older writer can create the journal object the new one is about to
    # fence. The new writer reads it, so the record of a tool call the older
    # writer may have started is not lost, and fences after it, so nothing the
    # older writer sends later reaches the journal.
    test "reads a record the older writer created while being fenced, and none after", %{memory: memory} do
      parent = self()
      old = [bucket: {HookedBucket, {memory, fn _key -> :ok end}}, key: "a", epoch: 1]
      assert :ok = ObjectStore.append_journal([{:resume, 1, nil}], old)

      hook = fn key ->
        if String.contains?(key, "/wal/") and Process.get(:raced) == nil and self() == parent do
          Process.put(:raced, true)
          # The new writer's manifest is already there, so the older writer is
          # told the append failed even though its object was created.
          assert ObjectStore.append_journal([{:resume, 2, nil}], old) == {:error, :fenced}
        end
      end

      new = [bucket: {HookedBucket, {memory, hook}}, key: "a", epoch: 2]

      assert ObjectStore.load_journal(new) == {:ok, [{:resume, 1, nil}, {:resume, 2, nil}]}
      assert ObjectStore.append_journal([{:resume, 3, nil}], old) == {:error, :fenced}
      assert :ok = ObjectStore.append_journal([{:resume, 4, nil}], new)
      assert ObjectStore.load_journal(new) == {:ok, [{:resume, 1, nil}, {:resume, 2, nil}, {:resume, 4, nil}]}
    end

    # Clearing the journal deletes the fence, so an older writer whose next
    # journal object was in the cleared range could create it again. Its
    # append still has to fail, or it would act on a record nobody reads.
    test "refuses an older writer whose next journal object was cleared", %{store_opts: opts} do
      old = Keyword.put(opts, :epoch, 1)
      new = Keyword.put(opts, :epoch, 2)
      assert :ok = ObjectStore.append_journal([{:resume, 1, nil}], old)

      # Another process, as when a new owner takes the session over while the
      # old one is still running.
      Task.await(
        Task.async(fn ->
          assert ObjectStore.load_journal(new) == {:ok, [{:resume, 1, nil}]}
          assert :ok = ObjectStore.save(Snapshot.new(%{}), new)
          assert :ok = ObjectStore.clear_journal(new)
        end)
      )

      assert ObjectStore.append_journal([{:resume, 2, nil}], old) == {:error, :fenced}
    end

    # The older writer can commit its next manifest between the new writer's
    # read of the latest one and its claim. The claim then retries after it,
    # rather than failing the new writer's load.
    test "a claim that loses to the older writer's save claims after it", %{memory: memory} do
      parent = self()
      old = [bucket: {HookedBucket, {memory, fn _key -> :ok end}}, key: "a", epoch: 1]
      assert :ok = ObjectStore.append_journal([{:resume, 1, nil}], old)
      saved = Snapshot.new(%{messages: [Message.user("saved by the older writer")]})

      hook = fn key ->
        if String.contains?(key, "/manifest/") and Process.get(:raced) == nil and self() == parent do
          Process.put(:raced, true)
          assert :ok = ObjectStore.save(saved, old)
        end
      end

      new = [bucket: {HookedBucket, {memory, hook}}, key: "a", epoch: 2]

      assert ObjectStore.load(new) == {:ok, saved}
      assert ObjectStore.append_journal([{:resume, 2, nil}], old) == {:error, :fenced}
    end

    test "manifests do not pile up as the session changes owners", %{store_opts: opts, memory: memory} do
      for epoch <- 1..8 do
        writer = Keyword.put(opts, :epoch, epoch)
        assert {:ok, _} = ObjectStore.load_journal(writer)
        assert :ok = ObjectStore.append_journal([{:resume, epoch, nil}], writer)
        assert :ok = ObjectStore.save(Snapshot.new(%{messages: [Message.user("turn #{epoch}")]}), writer)
        assert :ok = ObjectStore.clear_journal(writer)
      end

      {:ok, manifests} = Memory.list(memory, "condukt/sessions/a/manifest/", nil)
      assert length(manifests) <= 3
    end

    # Two takeovers later, the manifests the oldest writer would collide with
    # are deleted and its fence object is cleared. It still has to be refused,
    # or a save that rewrites the history deletes segments the current
    # manifest points to.
    test "refuses a writer two owners back", %{store_opts: opts} do
      first = Keyword.put(opts, :epoch, 1)
      long = for n <- 1..3, do: Message.user("turn #{n}")
      assert :ok = ObjectStore.save(Snapshot.new(%{messages: long}), first)

      Task.await(
        Task.async(fn ->
          second = Keyword.put(opts, :epoch, 2)
          assert {:ok, _} = ObjectStore.load(second)
          assert :ok = ObjectStore.save(Snapshot.new(%{messages: long ++ [Message.user("turn 4")]}), second)
          assert :ok = ObjectStore.clear_journal(second)
        end)
      )

      current = Task.await(Task.async(fn -> ObjectStore.load(Keyword.put(opts, :epoch, 3)) end))
      assert {:ok, %{messages: [_, _, _, _]}} = current

      assert ObjectStore.append_journal([{:resume, 1, nil}], first) == {:error, :fenced}
      assert ObjectStore.save(Snapshot.new(%{messages: [Message.user("rewritten")]}), first) == {:error, :fenced}
      assert ObjectStore.clear(first) == {:error, :fenced}
      assert ObjectStore.load(Keyword.put(opts, :epoch, 3)) == current
    end

    # The owner between them claimed but stopped before it wrote anything else.
    test "refuses a writer two owners back when the owner between them only claimed", %{store_opts: opts} do
      first = Keyword.put(opts, :epoch, 1)
      assert :ok = ObjectStore.save(Snapshot.new(%{messages: [Message.user("kept")]}), first)

      for epoch <- [2, 3] do
        Task.await(Task.async(fn -> assert {:ok, _} = ObjectStore.load(Keyword.put(opts, :epoch, epoch)) end))
      end

      assert ObjectStore.clear(first) == {:error, :fenced}
      assert {:ok, %{messages: [%{content: "kept"}]}} = ObjectStore.load(Keyword.put(opts, :epoch, 3))
    end

    test "a write at an epoch older than the session's is refused", %{store_opts: opts} do
      assert :ok = ObjectStore.save(Snapshot.new(%{}), Keyword.put(opts, :epoch, 5))
      assert ObjectStore.append_journal([{:resume, 1, nil}], Keyword.put(opts, :epoch, 4)) == {:error, :fenced}
    end

    test "reading without an epoch does not fence the writer", %{store_opts: opts} do
      writer = Keyword.put(opts, :epoch, 3)

      assert :ok = ObjectStore.append_journal([{:resume, 1, nil}], writer)
      assert ObjectStore.load_journal(opts) == {:ok, [{:resume, 1, nil}]}
      assert ObjectStore.load(opts) == :not_found
      assert :ok = ObjectStore.append_journal([{:resume, 2, nil}], writer)
    end
  end

  describe "segments" do
    test "a save stores only the messages after the stored ones", %{store_opts: opts, memory: memory} do
      first = [Message.user("one"), Message.assistant("two")]
      second = first ++ [Message.user("three")]

      last = Snapshot.new(%{messages: second, model: "m"})

      assert :ok = ObjectStore.save(Snapshot.new(%{messages: first}), opts)
      assert :ok = ObjectStore.save(Snapshot.new(%{messages: second}), opts)
      assert :ok = ObjectStore.save(last, opts)

      assert ObjectStore.load(opts) == {:ok, last}
      assert [one, two] = Enum.map(segments(memory), &length(read!(memory, &1)))
      assert {one, two} == {2, 1}
    end

    test "a history that no longer starts with the stored one is written whole", %{
      store_opts: opts,
      memory: memory
    } do
      assert :ok = ObjectStore.save(Snapshot.new(%{messages: [Message.user("one")]}), opts)
      assert :ok = ObjectStore.save(Snapshot.new(%{messages: [Message.user("one"), Message.user("two")]}), opts)

      compacted = [Message.user("summary"), Message.user("two")]
      snapshot = Snapshot.new(%{messages: compacted})
      assert :ok = ObjectStore.save(snapshot, opts)

      assert ObjectStore.load(opts) == {:ok, snapshot}
      assert [segment] = segments(memory)
      assert read!(memory, segment) == compacted
    end

    test "clearing the journal removes its objects", %{store_opts: opts, memory: memory} do
      assert :ok = ObjectStore.append_journal([{:resume, 1, nil}], opts)
      assert :ok = ObjectStore.append_journal([{:resume, 2, nil}], opts)
      assert :ok = ObjectStore.clear_journal(opts)

      assert {:ok, []} = Memory.list(memory, "condukt/sessions/a/wal/", nil)
    end
  end

  test "encrypts every object it writes", %{memory: memory} do
    opts = [
      bucket: {Memory, memory},
      key: "a",
      encrypt: &:crypto.exor(&1, :binary.copy(<<42>>, byte_size(&1))),
      decrypt: &:crypto.exor(&1, :binary.copy(<<42>>, byte_size(&1)))
    ]

    snapshot = Snapshot.new(%{messages: [Message.user("plaintext secret")]})
    assert :ok = ObjectStore.save(snapshot, opts)
    assert :ok = ObjectStore.append_journal([{:run_start, 1, %{message: Message.user("journal secret")}}], opts)

    assert ObjectStore.load(opts) == {:ok, snapshot}
    {:ok, keys} = Memory.list(memory, "", nil)
    refute Enum.any?(keys, &(memory |> Memory.get(&1) |> elem(1) |> String.contains?("secret")))
  end

  test "rejects a key an object key cannot carry", %{store_opts: opts} do
    assert_raise ArgumentError, fn -> ObjectStore.load(Keyword.put(opts, :key, "a b")) end
  end

  defp segments(memory) do
    {:ok, keys} = Memory.list(memory, "condukt/sessions/a/segments/", nil)
    keys
  end

  defp read!(memory, key) do
    {:ok, body} = Memory.get(memory, key)
    :erlang.binary_to_term(body)
  end
end

# Runs against a real S3 API when one is configured, such as a local MinIO's
# bucket:
#
#   CONDUKT_S3_ENDPOINT=http://127.0.0.1:9000 CONDUKT_S3_BUCKET=condukt \
#   CONDUKT_S3_ACCESS_KEY_ID=... CONDUKT_S3_SECRET_ACCESS_KEY=... \
#   mix test test/condukt/session_store_object_store_test.exs
if System.get_env("CONDUKT_S3_ENDPOINT") do
  defmodule Condukt.SessionStore.ObjectStoreS3Test do
    use ExUnit.Case, async: true
    use Condukt.SessionStore.Conformance, store: Condukt.SessionStore.ObjectStore

    alias Condukt.SessionStore.ObjectStore
    alias Condukt.SessionStore.ObjectStore.S3

    setup do
      bucket =
        {S3,
         endpoint: System.fetch_env!("CONDUKT_S3_ENDPOINT"),
         bucket: System.fetch_env!("CONDUKT_S3_BUCKET"),
         region: System.get_env("CONDUKT_S3_REGION", "us-east-1"),
         access_key_id: System.fetch_env!("CONDUKT_S3_ACCESS_KEY_ID"),
         secret_access_key: System.fetch_env!("CONDUKT_S3_SECRET_ACCESS_KEY")}

      prefix = "condukt-test/#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"

      %{
        bucket: bucket,
        store_opts: [bucket: bucket, prefix: prefix, key: "a"],
        other_store_opts: [bucket: bucket, prefix: prefix, key: "b"]
      }
    end

    test "the service refuses a create whose key exists", %{bucket: {S3, config}} do
      key = "condukt-test/#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}/object"

      assert :ok = S3.create(config, key, "first")
      assert S3.create(config, key, "second") == {:error, :exists}
      assert S3.get(config, key) == {:ok, "first"}
      assert :ok = S3.delete(config, key)
      assert S3.get(config, key) == :not_found
    end

    test "a newer epoch fences the older writer", %{store_opts: opts} do
      assert :ok = ObjectStore.append_journal([{:resume, 1, nil}], Keyword.put(opts, :epoch, 1))
      assert ObjectStore.load_journal(Keyword.put(opts, :epoch, 2)) == {:ok, [{:resume, 1, nil}]}
      assert ObjectStore.append_journal([{:resume, 2, nil}], Keyword.put(opts, :epoch, 1)) == {:error, :fenced}
    end

    test "lists past a page of keys", %{bucket: {S3, config}} do
      prefix = "condukt-test/#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}/"
      keys = for n <- 1..1005, do: prefix <> String.pad_leading("#{n}", 5, "0")

      keys
      |> Task.async_stream(&S3.create(config, &1, "x"), max_concurrency: 32)
      |> Stream.run()

      assert S3.list(config, prefix, nil) == {:ok, keys}
      assert {:ok, [_ | _] = after_1000} = S3.list(config, prefix, Enum.at(keys, 999))
      assert after_1000 == Enum.drop(keys, 1000)
    end
  end
end
