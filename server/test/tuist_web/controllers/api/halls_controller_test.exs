defmodule TuistWeb.API.HallsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    member = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: user)
    :ok = Accounts.add_user_to_organization(member, organization, role: :user)

    %{
      user: user,
      member: member,
      token: token(user),
      path: "/api/accounts/#{organization.account.name}/halls"
    }
  end

  test "members talk in a hall and direct conversations over the API without caching", %{
    member: member,
    token: token,
    path: path
  } do
    hall = token |> post_as(path, %{request_id: Ecto.UUID.generate(), name: "general"}) |> json_response(200)
    assert %{"kind" => "hall", "name" => "general", "messages" => []} = hall

    sent =
      member
      |> token()
      |> post_as("#{path}/#{hall["id"]}/messages", %{request_id: Ecto.UUID.generate(), content: "Morning"})
      |> json_response(200)

    assert %{"messages" => [%{"body" => "Morning", "mine" => true, "author" => %{"handle" => handle}}]} = sent
    assert handle == member.account.name

    conn = build_conn() |> put_req_header("authorization", "Bearer #{token}") |> get(path)
    assert %{"halls" => [%{"unread" => 1}], "directs" => []} = json_response(conn, 200)
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert %{"read_position" => 1} = token |> post_as("#{path}/#{hall["id"]}/read", %{position: 1}) |> json_response(200)

    assert %{"people" => [%{"id" => member_id}]} =
             build_conn()
             |> put_req_header("authorization", "Bearer #{token}")
             |> get("#{path}/people")
             |> json_response(200)

    assert member_id == member.id

    assert %{"kind" => "direct", "members" => [%{"id" => ^member_id}]} =
             token
             |> post_as("#{path}/directs", %{request_id: Ecto.UUID.generate(), user_ids: [member.id]})
             |> json_response(200)

    assert %{"message" => "A hall with this name already exists."} =
             member
             |> token()
             |> post_as(path, %{request_id: Ecto.UUID.generate(), name: "General"})
             |> json_response(409)

    assert token |> post_as(path, %{request_id: "nope", name: "x"}) |> json_response(400)
  end

  test "hides halls from people outside the organization and from personal accounts", %{user: user, path: path} do
    stranger = token(AccountsFixtures.user_fixture())
    assert build_conn() |> put_req_header("authorization", "Bearer #{stranger}") |> get(path) |> json_response(404)

    personal = "/api/accounts/#{user.account.name}/halls"
    assert build_conn() |> put_req_header("authorization", "Bearer #{token(user)}") |> get(personal) |> json_response(404)
    assert build_conn() |> get(path) |> json_response(401)
  end

  defp token(user) do
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")
    token
  end

  defp post_as(token, path, body) do
    build_conn() |> put_req_header("authorization", "Bearer #{token}") |> post(path, body)
  end
end
