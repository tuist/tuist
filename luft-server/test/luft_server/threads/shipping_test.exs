defmodule LuftServer.Threads.ShippingTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Lease
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads.Approval
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Shipping
  alias LuftServer.Threads.Thread

  @base String.duplicate("a", 40)
  @head String.duplicate("b", 40)

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => "1"},
        tokens: %{
          "access_token" => "owner-token",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    thread =
      Repo.insert!(%Thread{
        account_id: 10,
        account_handle: "team",
        owner_id: 1,
        owner_session_id: session.id,
        request_id: Ecto.UUID.generate(),
        request_hash: <<1>>,
        title: "Ship",
        goal: "Change",
        provider: "anthropic",
        model: "model",
        repository: "owner/repo",
        base_branch: "main",
        branch: "reviewed",
        base_sha: @base,
        sandbox_id: Ecto.UUID.generate(),
        workspace_ready: true
      })

    test = self()

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer owner-token"]

      if conn.request_path == "/api/accounts/team/luft-context" do
        Req.Test.json(conn, %{
          user_id: 1,
          account_id: 10,
          organization_id: nil,
          can_create_threads: true,
          people: []
        })
      else
        assert conn.request_path == "/api/accounts/team/workspace-capabilities"
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        body = Jason.decode!(raw)
        send(test, {:capability, body["operation"]})

        result =
          case body["operation"] do
            "repository_authorize" ->
              %{name: "owner/repo", default_branch: "main", size: 1}

            op when op in ["show", "acquire"] ->
              %{id: thread.sandbox_id, account_id: 10, state: "running"}

            "release" ->
              %{}

            "exec" ->
              output = if Enum.at(body["argv"], 2) =~ "commit-tree", do: @head, else: "{}"
              %{exit_code: 0, stdout: output}

            "repository_review" ->
              "reviewed diff"

            "repository_publish" ->
              assert body["snapshot"]["operation_id"] == thread.id
              assert body["diff"] == "reviewed diff"
              %{head_sha: @head}

            "publication_reconcile" ->
              %{request_id: body["request_id"], head_sha: @head, target_branch: "reviewed"}
          end

        if body["operation"] == "repository_publish" and Process.get(:uncertain_ship) do
          conn |> Plug.Conn.put_status(409) |> Req.Test.json(%{code: "shipping_uncertain"})
        else
          Req.Test.json(conn, %{result: result})
        end
      end
    end)

    %{thread: thread}
  end

  test "preview, approved execution and read-only reconciliation use the owner's real capability transport",
       %{thread: thread} do
    {approval, run} = approved(thread)

    assert {:ok, %{head_sha: @head, target_branch: "reviewed"}} =
             Shipping.execute(thread, approval, run)

    assert_received {:capability, "repository_publish"}
    assert {:ok, %{head_sha: @head}} = Shipping.reconcile(thread, approval)
    assert_received {:capability, "publication_reconcile"}
    refute_received {:capability, "repository_publish"}
  end

  test "uncertain publication is not made successful and reconciliation does not send another write",
       %{thread: thread} do
    {approval, run} = approved(thread)
    Process.put(:uncertain_ship, true)
    assert {:error, :shipping_uncertain} = Shipping.execute(thread, approval, run)
    assert_received {:capability, "repository_publish"}
    assert {:ok, %{head_sha: @head}} = Shipping.reconcile(thread, approval)
    refute_received {:capability, "repository_publish"}
  end

  test "a stale run or modified approval cannot dispatch publication", %{thread: thread} do
    {approval, run} = approved(thread)
    assert {:error, :stale_run} = Shipping.execute(thread, approval, %{run | attempt: 0})

    assert {:error, :shipping_approval_invalid} =
             Shipping.execute(thread, %{approval | diff: "forged"}, run)

    refute_received {:capability, "repository_publish"}
  end

  defp approved(thread) do
    assert {:ok, preview} = Shipping.preview(%{id: 1}, thread)
    assert preview.diff == "reviewed diff"

    approval =
      Repo.insert!(
        struct!(
          Approval,
          preview
          |> Map.delete(:actor)
          |> Map.merge(%{
            status: :approved,
            approved_by_id: 1,
            approved_at: DateTime.utc_now(:second)
          })
        )
      )

    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        approval_id: approval.id,
        kind: "ship",
        status: "running",
        attempt: 1
      })

    Lease.want(thread.id, "thread")

    Repo.query!(
      "UPDATE agent_sessions SET epoch=1, lease_expires_at=CURRENT_TIMESTAMP + interval '60 seconds' WHERE id=$1",
      [thread.id]
    )

    {approval, run}
  end
end
