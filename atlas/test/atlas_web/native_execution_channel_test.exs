defmodule AtlasWeb.NativeExecutionChannelTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.AutomationsFixtures
  import Ecto.Query
  import Phoenix.ChannelTest, except: [connect: 3]

  alias Atlas.Automations.Executor
  alias Atlas.Automations.Native
  alias Atlas.Repo
  alias AtlasWeb.NativeExecutionChannel
  alias AtlasWeb.NativeSocket

  @endpoint AtlasWeb.Endpoint

  test "endpoint enables token extraction at socket level and credentials redact inspection" do
    {_, NativeSocket, opts} = Enum.find(@endpoint.__sockets__(), fn {path, _, _} -> path == "/native/socket" end)
    assert opts[:auth_token] == true
    refute inspect(%NativeSocket.Credential{token: "opaque-secret"}) =~ "opaque-secret"
  end

  test "authenticates, follows committed state, and stops after role revocation", %{conn: conn} do
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    {:ok, run} = Native.run(actor, workflow.id, revision.id, Ecto.UUID.generate(), %{})
    token = oauth_access_token_fixture(actor)

    assert {:ok, socket} =
             Phoenix.ChannelTest.connect(NativeSocket, %{"run_id" => run.id}, connect_info: %{auth_token: token})

    assert {:ok, first, socket} = subscribe_and_join(socket, NativeExecutionChannel, "execution:#{run.id}")
    assert first.status == "queued"
    assert {:ok, :ok} = Executor.advance(run.id)
    send(socket.channel_pid, :automation_changed)
    assert_push "snapshot", snapshot
    assert snapshot.sequence > first.sequence
    refute Map.has_key?(snapshot, :input)
    Repo.delete_all(from r in "user_roles", where: r.user_id == type(^actor.id, Ecto.UUID))
    monitor = Process.monitor(socket.channel_pid)
    send(socket.channel_pid, :automation_changed)
    assert_push "access_revoked", %{}
    assert_receive {:DOWN, ^monitor, :process, _, _}
  end

  test "rejects missing credentials and cannot join another execution", %{conn: conn} do
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write"]})
    {workflow, revision} = workflow_fixture(actor)
    {:ok, one} = Native.run(actor, workflow.id, revision.id, Ecto.UUID.generate(), %{})
    {:ok, two} = Native.run(actor, workflow.id, revision.id, Ecto.UUID.generate(), %{})
    assert :error = Phoenix.ChannelTest.connect(NativeSocket, %{"run_id" => one.id}, connect_info: %{})
    token = oauth_access_token_fixture(actor)
    {:ok, socket} = Phoenix.ChannelTest.connect(NativeSocket, %{"run_id" => one.id}, connect_info: %{auth_token: token})
    assert {:error, %{error: "forbidden"}} = subscribe_and_join(socket, NativeExecutionChannel, "execution:#{two.id}")
  end
end
