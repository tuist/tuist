defmodule LuftServer.Threads.ExecutionTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads.Execution
  alias LuftServer.Tuist.Scope

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    # Only the owner's subscription is connected; admission must use it.
    LuftServer.FakeOpenAI.connect(11)
    %{owner: session(11), author: session(12)}
  end

  test "a participant uses the owner's model and canonical authorized repository", context do
    stub()

    assert {:ok, admitted} =
             Execution.admit(scope(), context.owner, context.author, selection())

    assert admitted.repository == "canonical/repo"
    assert admitted.base_branch == "trunk"

    assert {:ok, %{repository: nil, base_branch: nil}} =
             Execution.admit(scope(), context.owner, context.author, %{
               selection()
               | repository: nil,
                 base_branch: "unused"
             })
  end

  test "revoked owner authority, wrong tenant and wrong author cannot queue work", context do
    stub(owner_allowed: false)

    assert {:error, _} = Execution.admit(scope(), context.owner, context.author, selection())

    stub(owner_account: 99)
    assert {:error, _} = Execution.admit(scope(), context.owner, context.author, selection())

    stub()
    assert {:error, _} = Execution.admit(scope(), context.owner, context.owner, selection())

    Repo.delete!(context.owner)
    _other_session = session(11)
    assert {:error, _} = Execution.admit(scope(), context.owner, context.author, selection())
  end

  test "unavailable models and invalid branches reject admission", context do
    stub()

    assert {:error, :model_unavailable} =
             Execution.admit(scope(), context.owner, context.author, %{
               selection()
               | model: "absent"
             })

    for branch <- ["../main", "main//topic", "main@{1}", String.duplicate("a", 256)] do
      assert {:error, :invalid_arguments} =
               Execution.admit(scope(), context.owner, context.author, %{
                 selection()
                 | base_branch: branch
               })
    end
  end

  defp stub(opts \\ []) do
    LuftServer.FakeOpenAI.stub(models: ["test-model"])

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      ["Bearer " <> token] = get_req_header(conn, "authorization")

      case conn.request_path do
        "/api/accounts/team/luft-context" ->
          id = String.to_integer(token)

          Req.Test.json(conn, %{
            user_id: id,
            account_id: if(id == 11, do: Keyword.get(opts, :owner_account, 21), else: 21),
            organization_id: 30,
            can_create_threads: id == 11 and Keyword.get(opts, :owner_allowed, true),
            people: [
              %{id: 11, handle: "owner", active: true},
              %{id: 12, handle: "author", active: true}
            ]
          })

        "/api/accounts/team/workspace-capabilities" ->
          assert token == "11"
          {:ok, body, conn} = read_body(conn)

          assert %{"operation" => "repository_authorize", "repository" => "alias/repo"} =
                   Jason.decode!(body)

          Req.Test.json(conn, %{
            result: %{name: "canonical/repo", default_branch: "trunk", size: 40}
          })
      end
    end)
  end

  defp scope do
    %Scope{
      user_id: 12,
      account_id: 21,
      organization_id: 30,
      people: [],
      can_create_threads: false
    }
  end

  defp selection do
    %{
      account_handle: "team",
      provider: "chatgpt",
      model: "test-model",
      repository: "alias/repo",
      base_branch: nil,
      runner_id: nil
    }
  end

  defp session(id) do
    {:ok, _token, session} =
      Sessions.create(%{
        claims: %{"sub" => to_string(id), "preferred_username" => "user-#{id}"},
        tokens: %{
          "access_token" => to_string(id),
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    session
  end
end
