defmodule Tuist.XcresultDrainTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.XcresultDrain

  @uid "b1abef64-43be-40c8-b78d-49d18c261fed\n"

  setup do
    directory = Path.join(System.tmp_dir!(), "xcresult-drain-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    state = %{directory: directory, stopped: false, stopping: false}
    %{directory: directory, state: state}
  end

  test "a serving queue stays running", %{state: state} do
    expect(Oban, :check_queue, fn _ -> %{paused: false, running: []} end)
    assert {:noreply, ^state} = XcresultDrain.handle_info(:poll, state)
  end

  test "a new queue resumes locally only without a drain request", %{state: state} do
    expect(Oban, :check_queue, fn _ -> %{paused: true, running: []} end)
    expect(Oban, :resume_queue, fn [queue: :process_xcresult, local_only: true] -> :ok end)
    assert {:noreply, ^state} = XcresultDrain.handle_info(:poll, state)
  end

  test "a completed drain cannot resume when its request disappears", %{state: state} do
    state = %{state | stopped: true}
    assert {:noreply, ^state} = XcresultDrain.handle_info(:poll, state)
  end

  test "ignores partial and invalid requests", %{directory: dir, state: state} do
    stub(Oban, :check_queue, fn _ -> %{paused: false, running: []} end)

    for request <- ["", "drain", String.trim(@uid), "../../another-pod\n"] do
      File.write!(Path.join(dir, "drain-request"), request)
      refute XcresultDrain.requested?(dir)
      assert {:noreply, ^state} = XcresultDrain.handle_info(:poll, state)
    end
  end

  test "pauses locally and waits for running work", %{directory: dir, state: state} do
    File.write!(Path.join(dir, "drain-request"), @uid)
    expect(Oban, :pause_queue, fn [queue: :process_xcresult, local_only: true] -> :ok end)
    expect(Oban, :check_queue, fn [queue: :process_xcresult] -> %{paused: true, running: [123]} end)
    assert {:noreply, ^state} = XcresultDrain.handle_info(:poll, state)
    refute File.exists?(Path.join(dir, "drain-complete"))
    assert XcresultDrain.requested?(dir)
  end

  test "an asynchronous pause is not sufficient", %{directory: dir, state: state} do
    File.write!(Path.join(dir, "drain-request"), @uid)
    expect(Oban, :pause_queue, fn _ -> :ok end)
    expect(Oban, :check_queue, fn _ -> %{paused: false, running: []} end)
    assert {:noreply, ^state} = XcresultDrain.handle_info(:poll, state)
    refute File.exists?(Path.join(dir, "drain-complete"))
  end

  test "acknowledges only after the empty queue supervisor is gone", %{directory: dir, state: state} do
    File.write!(Path.join(dir, "drain-request"), @uid)
    expect(Oban, :pause_queue, fn _ -> :ok end)
    expect(Oban, :check_queue, fn _ -> %{paused: true, running: []} end)
    expect(Oban, :stop_queue, fn [queue: :process_xcresult, local_only: true] -> :ok end)
    assert {:noreply, stopping} = XcresultDrain.handle_info(:poll, state)
    refute File.exists?(Path.join(dir, "drain-complete"))
    expect(Oban.Registry, :whereis, fn Oban, {:queue, "process_xcresult"} -> self() end)
    assert {:noreply, ^stopping} = XcresultDrain.handle_info(:poll, stopping)
    refute File.exists?(Path.join(dir, "drain-complete"))
    expect(Oban.Registry, :whereis, fn Oban, {:queue, "process_xcresult"} -> nil end)
    assert {:noreply, %{stopped: true}} = XcresultDrain.handle_info(:poll, stopping)
    assert File.read!(Path.join(dir, "drain-complete")) == @uid
  end

  test "a queue failure never acknowledges", %{directory: dir, state: state} do
    File.write!(Path.join(dir, "drain-request"), @uid)
    expect(Oban, :pause_queue, fn _ -> exit(:noproc) end)
    assert {:noreply, ^state} = XcresultDrain.handle_info(:poll, state)
    refute File.exists?(Path.join(dir, "drain-complete"))
  end
end
