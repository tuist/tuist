defmodule Condukt.SessionStore.DiskTest do
  use ExUnit.Case, async: true
  use Condukt.SessionStore.Conformance, store: Condukt.SessionStore.Disk

  alias Condukt.Message
  alias Condukt.SessionStore.Disk
  alias Condukt.SessionStore.Snapshot

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    %{store_opts: [cwd: tmp_dir, id: "a"], other_store_opts: [cwd: tmp_dir, id: "b"]}
  end

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

  # A record can hold an atom a freshly started VM has not created yet, such as
  # a tool's error reason. Reading it must not make the session unable to start.
  test "reads journal records holding atoms the VM does not have yet", %{store_opts: opts} do
    :ok = Disk.append_journal([{:run_start, 1, %{}}], opts)
    name = "condukt_unseen_#{System.unique_integer([:positive])}"
    term = <<131, 104, 2, 119, 5, "error", 119, byte_size(name), name::binary>>
    journal = Path.join([opts[:cwd], ".condukt", "sessions", "a.store.journal"])
    File.write!(journal, [<<byte_size(term)::unsigned-32>>, term], [:append])

    assert {:ok, [{:run_start, 1, %{}}, {:error, atom}]} = Disk.load_journal(opts)
    assert Atom.to_string(atom) == name
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

  # A process killed mid-append leaves part of a record behind. Everything
  # before it is intact and still has to load, and the next append has to land
  # after the last whole record rather than after the fragment.
  test "drops a record torn by a crash and appends after the last whole one", %{tmp_dir: tmp_dir} do
    opts = [cwd: tmp_dir, id: "torn"]
    journal = Path.join([tmp_dir, ".condukt", "sessions", "torn.store.journal"])

    assert :ok = Disk.append_journal([{:resume, 1, nil}], opts)
    whole = File.read!(journal)
    File.write!(journal, whole <> <<0, 0, 0, 200, 131, 104>>)

    assert Disk.load_journal(opts) == {:ok, [{:resume, 1, nil}]}
    assert File.read!(journal) == whole

    assert :ok = Disk.append_journal([{:resume, 2, nil}], opts)
    assert Disk.load_journal(opts) == {:ok, [{:resume, 1, nil}, {:resume, 2, nil}]}
  end

  # Reading past a torn record and appending after it would bury the fragment
  # mid-file, so a journal that cannot be cut back is reported, not read.
  test "reports a torn journal it cannot cut back", %{tmp_dir: tmp_dir} do
    opts = [cwd: tmp_dir, id: "readonly"]
    journal = Path.join([tmp_dir, ".condukt", "sessions", "readonly.store.journal"])

    assert :ok = Disk.append_journal([{:resume, 1, nil}], opts)
    File.write!(journal, File.read!(journal) <> <<0, 0, 0, 200>>)
    File.chmod!(journal, 0o444)
    on_exit(fn -> File.chmod(journal, 0o644) end)

    # Root ignores the permission, so there is nothing to observe there.
    case File.open(journal, [:append]) do
      {:ok, file} -> File.close(file)
      {:error, :eacces} -> assert {:error, :eacces} = Disk.load_journal(opts)
    end
  end

  test "keeps the journal next to a snapshot at a custom path", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "custom.session")

    assert :ok = Disk.append_journal([{:resume, 1, nil}], path: path, cwd: "/tmp")
    assert File.exists?(path <> ".journal")
  end
end
