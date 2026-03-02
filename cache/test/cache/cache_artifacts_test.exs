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
    key1 = "account/project/cas/AB/CD/artifact1"
    key2 = "account/project/cas/EF/GH/artifact2"
    key3 = "account/project/cas/IJ/KL/artifact3"

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
    key_a = "account/project/cas/AA/BB/artifact_a"
    key_b = "account/project/cas/CC/DD/artifact_b"

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
        "account/project/cas/#{String.pad_leading(Integer.to_string(i), 2, "0")}/artifact_#{i}"
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
end
