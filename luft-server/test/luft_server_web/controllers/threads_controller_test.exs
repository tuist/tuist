defmodule LuftServerWeb.ThreadsControllerTest do
  use LuftServerWeb.ConnCase, async: true

  alias LuftServer.Sessions

  defmodule Admission do
    @moduledoc false
    def admit(_, _, _, _), do: :ok
  end

  defmodule Router do
    use Phoenix.Router

    import Phoenix.ConnTest, only: []

    pipeline :local do
      plug :accepts, ["json"]
    end

    scope "/api/accounts/:account_handle" do
      pipe_through :local
      get "/threads", LuftServerWeb.ThreadsController, :index
      post "/threads", LuftServerWeb.ThreadsController, :create
      get "/threads/models", LuftServerWeb.ThreadsController, :models
      get "/threads/repositories", LuftServerWeb.ThreadsController, :repositories
      get "/threads/:id", LuftServerWeb.ThreadsController, :show
      post "/threads/:id/messages", LuftServerWeb.ThreadsController, :message
      post "/threads/:id/reauthorize", LuftServerWeb.ThreadsController, :reauthorize
      patch "/threads/:id", LuftServerWeb.ThreadsController, :update
    end
  end

  setup do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => "1"},
        tokens: %{
          "access_token" => "upstream",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    stub_scope()
    %{session: session}
  end

  test "local controller binds originating session, replays, and reports conflicts", ctx do
    attrs = %{
      request_id: Ecto.UUID.generate(),
      content: "Hi",
      provider: "chatgpt",
      model: "model"
    }

    conn = request(ctx.session, :post, "/threads", attrs)

    assert %{"id" => id, "messages" => [%{"content" => "Hi", "author" => %{"id" => 1}}]} =
             json_response(conn, 200)

    refute Map.has_key?(json_response(conn, 200), "owner_session_id")
    assert %{"id" => ^id} = ctx.session |> request(:post, "/threads", attrs) |> json_response(200)

    assert %{"code" => "request_conflict"} =
             ctx.session
             |> request(:post, "/threads", %{attrs | content: "Other"})
             |> json_response(409)

    assert %{"code" => "busy"} =
             ctx.session
             |> request(:post, "/threads/#{id}/messages", %{
               request_id: Ecto.UUID.generate(),
               content: "Follow up"
             })
             |> json_response(409)

    assert %{"threads" => [%{"id" => ^id}]} =
             ctx.session |> request(:get, "/threads") |> json_response(200)

    assert %{"archive_status" => "archived"} =
             ctx.session
             |> request(:patch, "/threads/#{id}", %{status: "archived"})
             |> json_response(200)
  end

  test "missing execution support is not reported as successful work", ctx do
    attrs = %{
      request_id: Ecto.UUID.generate(),
      content: "Hi",
      provider: "chatgpt",
      model: "model"
    }

    assert %{"code" => "execution_unavailable"} =
             ctx.session |> request(:post, "/threads", attrs, false) |> json_response(503)

    assert %{"threads" => []} = ctx.session |> request(:get, "/threads") |> json_response(200)
  end

  test "catalogs use the actual requesting session, not a Tuist thread proxy", ctx do
    LuftServer.FakeOpenAI.connect(1)
    LuftServer.FakeOpenAI.stub(models: ["model"])

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert get_req_header(conn, "authorization") == ["Bearer upstream"]

      case conn.request_path do
        "/api/accounts/team/luft-context" ->
          Req.Test.json(conn, %{
            user_id: 1,
            account_id: 100,
            organization_id: 10,
            can_create_threads: true,
            people: []
          })

        "/api/accounts/team/workspace-capabilities" ->
          {:ok, body, conn} = read_body(conn)
          assert Jason.decode!(body) == %{"operation" => "repositories"}
          Req.Test.json(conn, %{result: [%{name: "Org/Repo", default_branch: "main"}]})
      end
    end)

    assert %{"models" => [%{"id" => "model"}], "errors" => []} =
             ctx.session |> request(:get, "/threads/models") |> json_response(200)

    assert %{"repositories" => [%{"name" => "Org/Repo"}]} =
             ctx.session |> request(:get, "/threads/repositories") |> json_response(200)
  end

  test "scope outages, missing auth and malformed ids never reveal content", ctx do
    assert %{"error" => "unauthenticated"} =
             nil |> request(:get, "/threads") |> json_response(401)

    assert %{"message" => "Not found."} =
             ctx.session |> request(:get, "/threads/not-an-id") |> json_response(404)

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      Plug.Conn.send_resp(conn, 503, "private upstream detail")
    end)

    assert %{"error" => "tuist_unavailable"} =
             ctx.session |> request(:get, "/threads") |> json_response(502)

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      Plug.Conn.send_resp(conn, 403, "private upstream detail")
    end)

    assert %{"message" => "Not found."} =
             ctx.session |> request(:get, "/threads") |> json_response(404)
  end

  test "members can read only mentioned conversations and cannot archive", ctx do
    attrs = %{
      request_id: Ecto.UUID.generate(),
      content: "Hi @two",
      provider: "chatgpt",
      model: "model"
    }

    %{"id" => id} = ctx.session |> request(:post, "/threads", attrs) |> json_response(200)

    {:ok, _, member} =
      Sessions.create(%{
        claims: %{"sub" => "2"},
        tokens: %{"access_token" => "member", "refresh_token" => "refresh", "expires_in" => 3600}
      })

    stub_scope(2, false)
    assert %{"id" => ^id} = member |> request(:get, "/threads/#{id}") |> json_response(200)

    assert %{"message" => "Not found."} =
             member
             |> request(:patch, "/threads/#{id}", %{status: "archived"})
             |> json_response(404)

    assert %{"message" => "Not found."} =
             member |> request(:post, "/threads", attrs) |> json_response(404)

    stub_scope(3, false)

    {:ok, _, outsider} =
      Sessions.create(%{
        claims: %{"sub" => "3"},
        tokens: %{
          "access_token" => "outsider",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    assert %{"message" => "Not found."} =
             outsider |> request(:get, "/threads/#{id}") |> json_response(404)
  end

  test "dormant history exposes consent state and only authorizes future turns", ctx do
    alias LuftServer.Repo
    alias LuftServer.Threads.Run
    alias LuftServer.Threads.Thread
    import Ecto.Query

    attrs = %{
      request_id: Ecto.UUID.generate(),
      content: "Hi @two",
      provider: "chatgpt",
      model: "model"
    }

    created = ctx.session |> request(:post, "/threads", attrs) |> json_response(200)
    id = created["id"]
    assert created["reauthorization_required"] == false

    thread = Repo.get!(Thread, id)
    Repo.update!(Ecto.Changeset.change(thread, owner_session_id: nil))
    dormant = ctx.session |> request(:get, "/threads/#{id}") |> json_response(200)
    assert dormant["reauthorization_required"]
    assert dormant["can_reauthorize"]

    assert %{"code" => "busy"} =
             ctx.session |> request(:post, "/threads/#{id}/reauthorize") |> json_response(409)

    assert Repo.get!(Thread, id).owner_session_id == nil

    Repo.update_all(from(r in Run, where: r.thread_id == ^id), set: [status: "cancelled"])
    Repo.update!(Ecto.Changeset.change(Repo.get!(Thread, id), agent_status: "idle"))

    {:ok, _, reader} =
      Sessions.create(%{
        claims: %{"sub" => "2"},
        tokens: %{"access_token" => "reader", "refresh_token" => "reader", "expires_in" => 3600}
      })

    stub_scope(2, false)
    shared = reader |> request(:get, "/threads/#{id}") |> json_response(200)
    assert shared["reauthorization_required"]
    refute shared["can_reauthorize"]
    assert reader |> request(:post, "/threads/#{id}/reauthorize") |> Map.get(:status) == 404
    assert Repo.get!(Thread, id).owner_session_id == nil
    stub_scope(1, false)
    assert ctx.session |> request(:post, "/threads/#{id}/reauthorize") |> Map.get(:status) == 404
    assert Repo.get!(Thread, id).owner_session_id == nil
    stub_scope()
    authorized = ctx.session |> request(:post, "/threads/#{id}/reauthorize") |> json_response(200)
    refute authorized["reauthorization_required"]
    assert Repo.get!(Thread, id).owner_session_id == ctx.session.id
    assert Repo.all(from r in Run, where: r.thread_id == ^id, select: r.status) == ["cancelled"]
    assert length(authorized["messages"]) == 1

    # A once-valid binding also becomes dormant when its persisted session expires.
    Repo.update!(Ecto.Changeset.change(ctx.session, expires_at: ~U[2020-01-01 00:00:00Z]))

    {:ok, _, fresh} =
      Sessions.create(%{
        claims: %{"sub" => "1"},
        tokens: %{"access_token" => "new", "refresh_token" => "new", "expires_in" => 3600}
      })

    assert (fresh
            |> request(:get, "/threads/#{id}")
            |> json_response(200))["reauthorization_required"]

    refute (fresh
            |> request(:post, "/threads/#{id}/reauthorize")
            |> json_response(200))["reauthorization_required"]

    assert Repo.get!(Thread, id).owner_session_id == fresh.id
  end

  defp stub_scope(id \\ 1, can_create \\ true) do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert conn.request_path == "/api/accounts/team/luft-context"

      Req.Test.json(conn, %{
        user_id: id,
        account_id: 100,
        organization_id: 10,
        can_create_threads: can_create,
        people: [
          %{id: 1, handle: "one", active: true},
          %{id: 2, handle: "two", active: true},
          %{id: 3, handle: "three", active: true}
        ]
      })
    end)
  end

  defp request(session, method, path, body \\ %{}, execution \\ true) do
    conn = Map.put(build_conn(), :secret_key_base, String.duplicate("a", 64))

    conn =
      conn
      |> assign(:session, session)
      |> assign(:threads_execution, if(execution, do: Admission))

    conn = %{
      conn
      | method: method |> to_string() |> String.upcase(),
        request_path: "/api/accounts/team" <> path,
        path_info: String.split("/api/accounts/team" <> path, "/", trim: true),
        body_params: body |> Jason.encode!() |> Jason.decode!(),
        params: %{}
    }

    Router.call(conn, Router.init([]))
  end
end
