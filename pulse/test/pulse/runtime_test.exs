defmodule Pulse.RuntimeTest do
  use Pulse.Test.Case, async: true

  alias Pulse.ObjectStore.NIF
  alias Pulse.Runtime
  alias Pulse.Runtime.Supervision
  alias Pulse.Storage.Memory
  alias Pulse.Test.RuntimeStatusServer

  test "unscoped child specifications preserve production start modules" do
    child = {Memory, []}
    expected = Supervisor.child_spec(child, [])
    assert Runtime.with(nil, fn -> Runtime.child_spec(child) end) == expected

    assert Runtime.with(nil, fn -> Supervision.init([child], strategy: :one_for_one) end) ==
             Supervisor.init([child], strategy: :one_for_one)
  end

  test "owned child specifications preserve module metadata" do
    spec = Runtime.child_spec({Memory, []})
    assert spec.modules == [Memory]
    assert {Runtime, :start_child, [_runtime, _start]} = spec.start
  end

  test "owned servers delegate status redaction" do
    server = start_supervised!({RuntimeStatusServer, secret: "must-not-appear"})
    assert :sys.get_status(server) |> inspect(limit: :infinity) =~ "redacted"
    refute :sys.get_status(server) |> inspect(limit: :infinity) =~ "must-not-appear"
  end

  test "native object-store capability matches the bounded retention API" do
    assert :ok = Pulse.ObjectStore.ensure_retention_api!()
    assert NIF.retention_api_version() == 1
  end
end
