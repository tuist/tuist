defmodule Cache.CacheArtifactsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.CacheArtifacts
  alias Cache.CacheArtifactsBuffer
  alias Cache.Disk
  alias Cache.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)

    if pid = Process.whereis(CacheArtifactsBuffer) do
      Sandbox.allow(Repo, self(), pid)
      CacheArtifactsBuffer.reset()
    end

    {:ok, storage_dir} = Briefly.create(directory: true)
    stub(Disk, :storage_dir, fn -> storage_dir end)

    {:ok, storage_dir: storage_dir}
  end

  test "returns empty list when no keys match" do
    result = CacheArtifacts.existing_keys(["fake/key1", "fake/key2"])
    assert result == []
  end

  test "returns all keys when all match" do
    key1 = "account/project/xcode/AB/CD/artifact1"
    key2 = "account/project/xcode/EF/GH/artifact2"
    key3 = "account/project/xcode/IJ/KL/artifact3"

    path1 = Disk.artifact_path(key1)
    path2 = Disk.artifact_path(key2)
    path3 = Disk.artifact_path(key3)

    File.mkdir_p!(Path.dirname(path1))
    File.mkdir_p!(Path.dirname(path2))
    File.mkdir_p!(Path.dirname(path3))
    File.write!(path1, "content1")
    File.write!(path2, "content2")
    File.write!(path3, "content3")

    :ok = CacheArtifacts.track_artifact_access(key1)
    :ok = CacheArtifacts.track_artifact_access(key2)
    :ok = CacheArtifacts.track_artifact_access(key3)
    :ok = CacheArtifactsBuffer.flush()

    result = CacheArtifacts.existing_keys([key1, key2, key3])
    assert Enum.sort(result) == Enum.sort([key1, key2, key3])
  end

  test "returns only matching keys" do
    key_a = "account/project/xcode/AA/BB/artifact_a"
    key_b = "account/project/xcode/CC/DD/artifact_b"

    path_a = Disk.artifact_path(key_a)
    path_b = Disk.artifact_path(key_b)

    File.mkdir_p!(Path.dirname(path_a))
    File.mkdir_p!(Path.dirname(path_b))
    File.write!(path_a, "content_a")
    File.write!(path_b, "content_b")

    :ok = CacheArtifacts.track_artifact_access(key_a)
    :ok = CacheArtifacts.track_artifact_access(key_b)
    :ok = CacheArtifactsBuffer.flush()

    result = CacheArtifacts.existing_keys([key_a, key_b, "fake/key_c", "fake/key_d"])
    assert Enum.sort(result) == Enum.sort([key_a, key_b])
  end

  test "handles empty input list" do
    result = CacheArtifacts.existing_keys([])
    assert result == []
  end

  test "handles large batch" do
    keys =
      Enum.map(1..100, fn i ->
        "account/project/xcode/#{String.pad_leading(Integer.to_string(i), 2, "0")}/artifact_#{i}"
      end)

    Enum.each(keys, fn key ->
      path = Disk.artifact_path(key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content_#{key}")
      :ok = CacheArtifacts.track_artifact_access(key)
    end)

    :ok = CacheArtifactsBuffer.flush()

    result = CacheArtifacts.existing_keys(keys)
    assert Enum.sort(result) == Enum.sort(keys)
  end

  describe "content digests" do
    setup %{storage_dir: _storage_dir} do
      key = "account/project/module/builds/AB/CD/abcd/Module.zip"
      path = Disk.artifact_path(key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "artifact")
      {:ok, key: key, digest: String.duplicate("ab", 32)}
    end

    test "is recorded, flushed, and read back", %{key: key, digest: digest} do
      :ok = CacheArtifacts.record_content_sha256(key, digest)
      :ok = CacheArtifactsBuffer.flush()

      assert CacheArtifacts.content_sha256(key) == digest
    end

    # An access and a digest for the same key are queued as separate entries, each
    # by a single insert, so neither can overwrite the other whatever the order.
    # Driven on a table no flusher reads, so nothing races the assertions.
    test "an access never replaces a queued digest, in either order", %{key: key, digest: digest} do
      table = :"content_digest_entries_#{System.unique_integer([:positive])}"
      :ets.new(table, [:set, :public, :named_table])
      now = DateTime.utc_now()

      for order <- [:digest_first, :access_first] do
        if order == :access_first, do: :ok = CacheArtifactsBuffer.enqueue_access(key, 8, now, table)
        :ok = CacheArtifactsBuffer.enqueue_content_sha256(key, 8, now, digest, table)
        if order == :digest_first, do: :ok = CacheArtifactsBuffer.enqueue_access(key, 8, now, table)

        assert CacheArtifactsBuffer.pending_content_sha256(key, table) == {:set, digest}

        assert [
                 {:artifact_accesses, %{^key => _access}},
                 {:artifact_content_sha256s, %{^key => %{content_sha256: ^digest}} = content_sha256s}
               ] = CacheArtifactsBuffer.flush_entries(table, 100)

        CacheArtifactsBuffer.write_batch(:artifact_content_sha256s, content_sha256s)
        assert CacheArtifactsBuffer.pending_content_sha256(key, table) == :keep
      end
    end

    # The row still holds the digest being replaced until the write commits, so a
    # read in between must keep answering from the queue, a cleared digest included.
    test "a queued digest stays visible until its row commits, even one that clears it", %{key: key, digest: digest} do
      table = :"content_digest_in_flight_#{System.unique_integer([:positive])}"
      :ets.new(table, [:set, :public, :named_table])
      now = DateTime.utc_now()
      stored = %{key: key, size_bytes: 8, last_accessed_at: now, content_sha256: digest}
      CacheArtifactsBuffer.write_batch(:artifact_content_sha256s, %{key => stored})

      :ok = CacheArtifactsBuffer.enqueue_content_sha256(key, 8, now, nil, table)
      assert [{:artifact_content_sha256s, content_sha256s}] = CacheArtifactsBuffer.flush_entries(table, 100)

      assert CacheArtifactsBuffer.pending_content_sha256(key, table) == {:set, nil}

      CacheArtifactsBuffer.write_batch(:artifact_content_sha256s, content_sha256s)
      assert CacheArtifactsBuffer.pending_content_sha256(key, table) == :keep
      assert CacheArtifacts.content_sha256(key) == nil
    end

    test "a digest recorded while an earlier one is being written survives that write", %{key: key, digest: digest} do
      table = :"content_digest_rerecorded_#{System.unique_integer([:positive])}"
      :ets.new(table, [:set, :public, :named_table])
      now = DateTime.utc_now()
      newer = String.duplicate("cd", 32)

      :ok = CacheArtifactsBuffer.enqueue_content_sha256(key, 8, now, digest, table)
      assert [{:artifact_content_sha256s, content_sha256s}] = CacheArtifactsBuffer.flush_entries(table, 100)
      :ok = CacheArtifactsBuffer.enqueue_content_sha256(key, 8, now, newer, table)

      CacheArtifactsBuffer.write_batch(:artifact_content_sha256s, content_sha256s)

      assert CacheArtifactsBuffer.pending_content_sha256(key, table) == {:set, newer}
    end

    test "only a digest write changes the stored digest", %{key: key, digest: digest} do
      now = DateTime.utc_now()

      write_digest = fn content_sha256 ->
        entry = %{key: key, size_bytes: 8, last_accessed_at: now, content_sha256: content_sha256}
        CacheArtifactsBuffer.write_batch(:artifact_content_sha256s, %{key => entry})
      end

      write_digest.(digest)
      assert CacheArtifacts.content_sha256(key) == digest

      CacheArtifactsBuffer.write_batch(:artifact_accesses, %{key => %{key: key, size_bytes: 8, last_accessed_at: now}})
      assert CacheArtifacts.content_sha256(key) == digest

      # The bytes on disk were published without a digest, so the old one would
      # describe a different object.
      write_digest.(nil)
      assert CacheArtifacts.content_sha256(key) == nil
    end
  end
end
