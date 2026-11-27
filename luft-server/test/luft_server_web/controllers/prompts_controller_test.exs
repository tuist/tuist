defmodule LuftServerWeb.PromptsControllerTest do
  use LuftServerWeb.ConnCase, async: true

  alias LuftServer.Prompts.Prompt
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServerWeb.Auth

  setup do
    {:ok, token, _session} =
      Sessions.create(%{
        claims: %{"sub" => "1"},
        tokens: %{
          "access_token" => "upstream",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    stub_scope()
    %{token: token}
  end

  test "standards are persisted, editable, resettable and shared by organization ID", ctx do
    assert %{"prompts" => prompts, "can_edit" => true} =
             ctx.token |> request(:get) |> json_response(200)

    assert Enum.sort(Enum.map(prompts, & &1["name"])) ==
             ~w(refactor-commits review ship summarize update-base)

    assert Enum.all?(prompts, & &1["standard"])
    assert Repo.aggregate(Prompt, :count) == 5
    original = Enum.find(prompts, &(&1["name"] == "ship"))["body"]

    assert %{"prompt" => %{"body" => "Check the Linux build.", "standard" => true}} =
             ctx.token
             |> request(:put, "/ship", %{title: "Ship safely", body: "Check the Linux build."})
             |> json_response(200)

    # A renamed account in the same organization sees the same persisted prompt.
    stub_scope(handle: "renamed", account: 101)

    assert %{"prompt" => %{"title" => "Ship safely"}} =
             ctx.token |> request(:get, "/ship", %{}, "renamed") |> json_response(200)

    stub_scope(organization: 20)

    assert %{"prompt" => %{"body" => ^original}} =
             ctx.token |> request(:get, "/ship") |> json_response(200)

    stub_scope()
    assert ctx.token |> request(:delete, "/ship") |> response(204)

    assert %{"prompt" => %{"body" => ^original, "title" => "Ship"}} =
             ctx.token |> request(:get, "/ship") |> json_response(200)
  end

  test "custom prompts can be created, updated and deleted without changing another organization",
       ctx do
    assert ctx.token
           |> request(:put, "/test-linux", %{title: "Test Linux", body: "Run the Linux checks."})
           |> json_response(200)

    assert ctx.token
           |> request(:put, "/test-linux", %{title: "Linux", body: "Run all Linux checks."})
           |> json_response(200)

    stub_scope(organization: 20)
    assert ctx.token |> request(:get, "/test-linux") |> json_response(404)
    assert ctx.token |> request(:delete, "/test-linux") |> response(204)

    stub_scope()

    assert %{"prompt" => %{"body" => "Run all Linux checks."}} =
             ctx.token |> request(:get, "/test-linux") |> json_response(200)

    assert ctx.token |> request(:delete, "/test-linux") |> response(204)
    assert ctx.token |> request(:get, "/test-linux") |> json_response(404)
  end

  test "members can read, but only admins may change prompts; current authorization wins", ctx do
    stub_scope(admin: false)
    assert %{"can_edit" => false} = ctx.token |> request(:get) |> json_response(200)
    assert ctx.token |> request(:put, "/ship", %{body: "Bypass review"}) |> json_response(403)
    assert ctx.token |> request(:delete, "/ship") |> json_response(403)

    stub_scope(organization: nil)
    assert ctx.token |> request(:get) |> json_response(404)
    stub_scope(status: 403)
    assert ctx.token |> request(:get) |> json_response(404)
    stub_scope(status: 503)
    assert ctx.token |> request(:get) |> json_response(503)
    assert get(build_conn(), "/api/accounts/team/prompts") |> json_response(401)
  end

  test "validation rejects invalid names and empty or oversized content", ctx do
    for {name, attrs} <- [
          {"Bad_name", %{title: "Name", body: "Body"}},
          {"test", %{title: "", body: "Body"}},
          {"test", %{title: String.duplicate("a", 81), body: "Body"}},
          {"test", %{title: "Name", body: "  "}},
          {"test", %{title: "Name", body: String.duplicate("é", 6001)}}
        ] do
      assert ctx.token |> request(:put, "/#{name}", attrs) |> json_response(422)
    end

    assert ctx.token
           |> request(:put, "/test", %{title: "Boundary", body: String.duplicate("é", 6000)})
           |> json_response(200)
  end

  test "cookie writes require same origin and prompt responses are not cached", ctx do
    conn = ctx.token |> request(:get)
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert build_conn()
           |> put_req_cookie(Auth.cookie_name(), ctx.token)
           |> put("/api/accounts/team/prompts/ship", %{title: "Ship", body: "Unsafe origin"})
           |> json_response(403)
  end

  defp request(token, method, suffix \\ "", body \\ %{}, handle \\ "team") do
    build_conn()
    |> put_req_cookie(Auth.cookie_name(), token)
    |> put_req_header("origin", "https://luft.test")
    |> dispatch(@endpoint, method, "/api/accounts/#{handle}/prompts#{suffix}", body)
  end

  defp stub_scope(opts \\ []) do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert conn.method == "GET"

      assert conn.request_path ==
               "/api/accounts/#{Keyword.get(opts, :handle, "team")}/luft-context"

      conn
      |> put_status(Keyword.get(opts, :status, 200))
      |> Req.Test.json(%{
        user_id: 1,
        account_id: Keyword.get(opts, :account, 100),
        organization_id: Keyword.get(opts, :organization, 10),
        can_create_threads: Keyword.get(opts, :admin, true),
        people: []
      })
    end)
  end
end
