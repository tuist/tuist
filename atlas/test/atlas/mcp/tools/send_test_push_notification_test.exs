defmodule Atlas.MCP.Tools.SendTestPushNotificationTest do
  use Atlas.MCP.ToolCase
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Atlas.PushFixtures

  alias Atlas.MCP.Tools.SendTestPushNotification
  alias Atlas.Push
  alias Atlas.Push.Config
  alias Atlas.Push.Workers.Deliver

  setup do
    stub(Config, :capabilities, fn -> %{"ios" => true, "android" => true} end)
    stub(Config, :available?, fn _platform, _environment -> true end)
    user = insert_user!()
    %{user: user, conn: mcp_conn(user)}
  end

  test "queues the generic notification for the caller's own registrations only", %{user: user, conn: conn} do
    assert {:ok, %{queued: 0}} = execute_tool(SendTestPushNotification, conn, %{})

    {:ok, mine} = Push.register(user, native_client_id(user), Ecto.UUID.generate(), ios_device())
    {:ok, _theirs} = Push.register(insert_user!(), Ecto.UUID.generate(), Ecto.UUID.generate(), ios_device())

    assert {:ok, %{queued: 1}} = execute_tool(SendTestPushNotification, conn, %{})

    assert [%Oban.Job{args: %{"registration_id" => registration_id, "kind" => "self_test", "screen" => "profile"}}] =
             all_enqueued(worker: Deliver)

    assert registration_id == mine.id
  end

  test "accepts no recipients or text and is rate limited", %{user: user, conn: conn} do
    other = insert_user!()

    assert {:error, "This tool takes no arguments."} =
             execute_tool(SendTestPushNotification, conn, %{"user_id" => other.id})

    assert {:error, "This tool takes no arguments."} = execute_tool(SendTestPushNotification, conn, %{"body" => "Hi"})
    assert {:error, message} = execute_tool(SendTestPushNotification, %{assigns: %{}}, %{})
    assert message =~ "authenticated"

    for _ <- 1..5, do: assert({:ok, _} = execute_tool(SendTestPushNotification, conn, %{}))
    assert {:error, message} = execute_tool(SendTestPushNotification, conn, %{})
    assert message =~ "Too many"
    refute user.id == other.id
  end
end
