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

    # Entries collapse per key until a flush, so a download's plain access queued
    # behind a completion must inherit the digest rather than replace its entry.
    # Driven on a table no flusher reads, so nothing races the assertions.
    test "a plain access queued behind a digest inherits it", %{key: key, digest: digest} do
      table = :"content_digest_merge_#{System.unique_integer([:positive])}"
      :ets.new(table, [:set, :public, :named_table])
      now = DateTime.utc_now()

      :ok = CacheArtifactsBuffer.enqueue_access_with_content_sha256(key, 8, now, digest, table)
      :ok = CacheArtifactsBuffer.enqueue_access(key, 8, now, table)
      assert CacheArtifactsBuffer.pending_content_sha256(key, table) == {:set, digest}

      assert [{:artifact_accesses, %{^key => %{content_sha256: {:set, ^digest}}}}] =
               CacheArtifactsBuffer.flush_entries(table, 100)

      :ok = CacheArtifactsBuffer.enqueue_access(key, 8, now, table)
      assert CacheArtifactsBuffer.pending_content_sha256(key, table) == :keep
    end

    test "only an entry that sets a digest changes the stored one", %{key: key, digest: digest} do
      write = fn content_sha256 ->
        entry = %{key: key, size_bytes: 8, last_accessed_at: DateTime.utc_now(), content_sha256: content_sha256}
        CacheArtifactsBuffer.write_batch(:artifact_accesses, %{key => entry})
      end

      write.({:set, digest})
      assert CacheArtifacts.content_sha256(key) == digest

      write.(:keep)
      assert CacheArtifacts.content_sha256(key) == digest

      # The bytes on disk were published without a digest, so the old one would
      # describe a different object.
      write.({:set, nil})
      assert CacheArtifacts.content_sha256(key) == nil
    end
  end
end
