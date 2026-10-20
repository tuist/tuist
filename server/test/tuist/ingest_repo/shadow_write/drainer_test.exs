defmodule Tuist.IngestRepo.ShadowWrite.DrainerTest do
  # Not async: the task supervisor and the drainer are registered by name, as
  # they are in the application.
  use ExUnit.Case, async: false

  alias Tuist.IngestRepo.ShadowWrite.Drainer

  @task_supervisor Tuist.IngestRepo.ShadowWrite.TaskSupervisor

  test "lets a mirror in flight finish before the task supervisor stops" do
    # The application's order: the task supervisor, then the drainer, so the
    # drainer is stopped first.
    {:ok, supervisor} =
      Supervisor.start_link([{Task.Supervisor, name: @task_supervisor}, Drainer], strategy: :one_for_one)

    test = self()

    {:ok, _pid} =
      Task.Supervisor.start_child(@task_supervisor, fn ->
        Process.sleep(200)
        send(test, :mirrored)
      end)

    :ok = Supervisor.stop(supervisor)

    # Stopping a task supervisor kills its tasks at once, because a task does
    # not trap exits. Arriving at all means the drainer held it back.
    assert_received :mirrored
  end
end
