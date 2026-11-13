defmodule Condukt.SessionStore.DiskTest do
  use ExUnit.Case, async: true

  alias Condukt.Message
  alias Condukt.SessionStore.Disk
  alias Condukt.SessionStore.Snapshot

  @moduletag :tmp_dir

  test "saves, loads, and clears snapshots", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "session.store")

    snapshot = %Snapshot{
      messages: [Message.user("persist this")],
      model: "anthropic:claude-sonnet-4-20250514",
      thinking_level: :medium,
      system_prompt: "disk prompt"
    }

    assert Disk.load(path: path, cwd: "/tmp") == :not_found
    assert :ok = Disk.save(snapshot, path: path, cwd: "/tmp")
    assert {:ok, ^snapshot} = Disk.load(path: path, cwd: "/tmp")
    assert :ok = Disk.clear(path: path, cwd: "/tmp")
    assert Disk.load(path: path, cwd: "/tmp") == :not_found
  end

  test "uses the default path under cwd", %{tmp_dir: tmp_dir} do
    path = Path.join([tmp_dir, ".condukt", "session.store"])

    snapshot = %Snapshot{
      messages: [Message.user("persist this too")],
      model: "openai:gpt-4o-mini",
      thinking_level: :high,
      system_prompt: "default path"
    }

    assert Disk.load(cwd: tmp_dir) == :not_found
    assert :ok = Disk.save(snapshot, cwd: tmp_dir)
    assert File.exists?(path)
    assert {:ok, ^snapshot} = Disk.load(cwd: tmp_dir)
  end

  test "loads legacy snapshots encoded without a version wrapper", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "legacy.session")

    snapshot = %Snapshot{
      messages: [Message.assistant("from legacy format")],
      model: "openai:gpt-4o",
      thinking_level: :low,
      system_prompt: "legacy snapshot"
    }

    assert :ok = File.write(path, :erlang.term_to_binary(snapshot))
    assert {:ok, ^snapshot} = Disk.load(path: path, cwd: "/tmp")
  end

  test "returns an error for invalid snapshots", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "invalid.session")
    assert :ok = File.write(path, "not a valid snapshot")
    assert Disk.load(path: path, cwd: "/tmp") == {:error, :invalid_snapshot}
  end

  test "clear succeeds for a missing snapshot file", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "missing.session")
    assert :ok = Disk.clear(path: path, cwd: "/tmp")
  end

  test "scopes snapshots by id when one is supplied", %{tmp_dir: tmp_dir} do
    expected_path = Path.join([tmp_dir, ".condukt", "sessions", "job-42.store"])

    snapshot_a = %Snapshot{messages: [Message.user("job 42")], model: "m", thinking_level: :low, system_prompt: nil}
    snapshot_b = %Snapshot{messages: [Message.user("job 99")], model: "m", thinking_level: :low, system_prompt: nil}

    assert :ok = Disk.save(snapshot_a, cwd: tmp_dir, id: "job-42")
    assert :ok = Disk.save(snapshot_b, cwd: tmp_dir, id: "job-99")
    assert File.exists?(expected_path)
    assert {:ok, ^snapshot_a} = Disk.load(cwd: tmp_dir, id: "job-42")
    assert {:ok, ^snapshot_b} = Disk.load(cwd: tmp_dir, id: "job-99")
  end
end
