defmodule LuftServerWeb.LoungesControllerTest do
  use LuftServerWeb.ConnCase, async: false

  alias LuftServer.Config
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServerWeb.Auth

  setup do
    %{session: session_for("1")}
  end

  defp session_for(subject) do
    {:ok, token, _session} =
      Sessions.create(%{
        claims: %{"sub" => subject, "preferred_username" => "person-#{subject}"},
        tokens: %{
          "access_token" => "upstream-access",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    token
  end

  defp stub_scope(user_id \\ 1) do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert conn.method == "GET"
      assert get_req_header(conn, "authorization") == ["Bearer upstream-access"]

      assert conn.request_path in [
               "/api/accounts/team/luft-context",
               "/api/accounts/other/luft-context"
             ]

      account_id = if conn.request_path =~ "/team/", do: 100, else: 101

      Req.Test.json(conn, %{
        user_id: user_id,
        account_id: account_id,
        organization_id: 10,
        people: Enum.map(1..3, &%{id: &1, handle: "person-#{&1}", active: true}),
        can_create_threads: false
      })
    end)
  end

  defp request(token, method, path, body \\ nil) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("origin", Config.public_url())
    |> put_req_cookie(Auth.cookie_name(), token)
    |> dispatch(@endpoint, method, path, if(body, do: Jason.encode!(body)))
  end

  test "local conversations enforce cookie origin and session revocation", %{session: token} do
    stub_scope()
    path = "/api/accounts/team/lounges"
    attrs = Jason.encode!(%{name: "general", request_id: Ecto.UUID.generate()})

    for origin <- [nil, "https://another.luft.test"] do
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_cookie(Auth.cookie_name(), token)

      conn = if origin, do: put_req_header(conn, "origin", origin), else: conn
      assert %{"error" => "forbidden_origin"} = conn |> post(path, attrs) |> json_response(403)
    end

    assert %{"lounges" => [], "directs" => []} =
             token |> request(:get, path) |> json_response(200)

    assert %{"error" => "unauthenticated"} =
             build_conn()
             |> put_req_cookie(Auth.cookie_name(), token)
             |> put_req_header("authorization", "Bearer invalid")
             |> get(path)
             |> json_response(401)

    token |> Sessions.get() |> Repo.delete!()

    assert %{"error" => "unauthenticated"} =
             token |> request(:get, path) |> json_response(401)
  end

  test "routed writes are idempotent and account scoping hides content", %{session: session} do
    stub_scope()
    attrs = %{name: "general", request_id: Ecto.UUID.generate()}
    lounge = session |> request(:post, "/api/accounts/team/lounges", attrs) |> json_response(200)
    id = lounge["id"]

    assert %{"id" => ^id, "kind" => "lounge"} =
             session |> request(:post, "/api/accounts/team/lounges", attrs) |> json_response(200)

    assert %{"code" => "request_conflict"} =
             session
             |> request(:post, "/api/accounts/team/lounges", %{attrs | name: "changed"})
             |> json_response(409)

    message = %{content: "hello", request_id: Ecto.UUID.generate()}

    for _ <- 1..2 do
      assert %{"last_position" => 1, "messages" => [%{"body" => "hello"}]} =
               session
               |> request(:post, "/api/accounts/team/lounges/#{id}/messages", message)
               |> json_response(200)
    end

    assert %{"code" => "request_conflict"} =
             session
             |> request(:post, "/api/accounts/team/lounges/#{id}/messages", %{
               message
               | content: "changed"
             })
             |> json_response(409)

    assert %{"read_position" => 1} =
             session
             |> request(:post, "/api/accounts/team/lounges/#{id}/read", %{position: 100})
             |> json_response(200)

    assert %{"messages" => []} =
             session
             |> request(:get, "/api/accounts/team/lounges/#{id}?before=1")
             |> json_response(200)

    for method <- [:get, :post] do
      path = "/api/accounts/other/lounges/#{id}" <> if(method == :post, do: "/messages", else: "")

      assert %{"message" => "Not found."} =
               session |> request(method, path, message) |> json_response(404)
    end
  end

  test "routed direct conversation cannot be read, listed or changed by a nonmember", %{
    session: session
  } do
    stub_scope()

    dm =
      session
      |> request(:post, "/api/accounts/team/lounges/directs", %{
        user_ids: [2],
        request_id: Ecto.UUID.generate()
      })
      |> json_response(200)

    id = dm["id"]
    stranger = session_for("3")
    stub_scope(3)

    assert %{"directs" => []} =
             stranger |> request(:get, "/api/accounts/team/lounges") |> json_response(200)

    for {method, suffix, body} <- [
          {:get, "", nil},
          {:post, "/messages", %{content: "no", request_id: Ecto.UUID.generate()}},
          {:post, "/read", %{position: 1}},
          {:post, "/members", %{user_ids: [3]}}
        ] do
      assert %{"message" => "Not found."} =
               stranger
               |> request(method, "/api/accounts/team/lounges/#{id}#{suffix}", body)
               |> json_response(404)
    end
  end

  test "routed pagination and read updates retain exclusive cursors and monotonic positions", %{
    session: session
  } do
    stub_scope()

    %{"id" => id} =
      session
      |> request(:post, "/api/accounts/team/lounges", %{
        name: "pagination",
        request_id: Ecto.UUID.generate()
      })
      |> json_response(200)

    for n <- 1..55 do
      session
      |> request(:post, "/api/accounts/team/lounges/#{id}/messages", %{
        content: "message #{n}",
        request_id: Ecto.UUID.generate()
      })
      |> json_response(200)
    end

    reader = session_for("2")
    stub_scope(2)

    assert %{"messages" => page, "has_more" => true, "next_before" => 6, "read_position" => 0} =
             reader |> request(:get, "/api/accounts/team/lounges/#{id}") |> json_response(200)

    assert Enum.map(page, & &1["position"]) == Enum.to_list(6..55)

    assert %{"messages" => older, "has_more" => false, "next_before" => nil} =
             reader
             |> request(:get, "/api/accounts/team/lounges/#{id}?before=6")
             |> json_response(200)

    assert Enum.map(older, & &1["position"]) == Enum.to_list(1..5)

    for {position, expected} <- [{30, 30}, {2, 30}, {1000, 55}] do
      assert %{"read_position" => ^expected} =
               reader
               |> request(:post, "/api/accounts/team/lounges/#{id}/read", %{position: position})
               |> json_response(200)
    end

    assert %{"message" => "The lounge request is invalid."} =
             reader
             |> request(:post, "/api/accounts/team/lounges/#{id}/read", %{position: nil})
             |> json_response(400)
  end

  test "upstream outages are gateway errors, not missing membership", %{session: session} do
    for status <- [500, 502, 503] do
      Req.Test.stub(LuftServer.Tuist, fn conn ->
        conn |> put_status(status) |> Req.Test.json(%{message: "unavailable"})
      end)

      assert %{"error" => "tuist_unavailable"} =
               session |> request(:get, "/api/accounts/team/lounges") |> json_response(502)
    end

    Req.Test.stub(LuftServer.Tuist, fn conn -> conn |> put_status(403) |> Req.Test.json(%{}) end)

    assert %{"message" => "Not found."} =
             session |> request(:get, "/api/accounts/team/lounges") |> json_response(404)
  end
end
