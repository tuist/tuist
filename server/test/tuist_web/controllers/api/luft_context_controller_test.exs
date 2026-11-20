defmodule TuistWeb.API.LuftContextControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.API.LuftContextController
  alias TuistWeb.Authentication

  setup do
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    member = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: user)
    :ok = Accounts.add_user_to_organization(member, organization, role: :user)
    %{user: user, member: member, organization: organization, account: organization.account}
  end

  test "admin and member get only the authorization projection, not conversations or credentials", %{
    user: user,
    member: member,
    organization: organization,
    account: account
  } do
    for {requester, can_create} <- [{user, true}, {member, false}] do
      conn = request(token(requester), account.name)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      assert json_response(conn, 200) == %{
               "user_id" => requester.id,
               "account_id" => account.id,
               "organization_id" => organization.id,
               "can_create_threads" => can_create,
               "people" => Enum.sort_by([person(user), person(member)], & &1["handle"])
             }
    end
  end

  test "viewers are members but cannot create threads", %{member: member, organization: organization, account: account} do
    Accounts.update_user_role_in_organization(member, organization, :viewer)
    assert %{"can_create_threads" => false} = member |> token() |> request(account.name) |> json_response(200)
  end

  test "only the owner can access a personal account and its sole person is self", %{user: user, member: member} do
    reject(FeatureFlags, :organization_luft_enabled?, 1)

    assert user |> token() |> request(user.account.name) |> json_response(200) == %{
             "user_id" => user.id,
             "account_id" => user.account.id,
             "organization_id" => nil,
             "can_create_threads" => true,
             "people" => [person(user)]
           }

    assert_not_found(request(token(member), user.account.name))
  end

  test "missing and foreign accounts have identical not found responses", %{account: account} do
    stranger = AccountsFixtures.user_fixture()
    assert_not_found(request(token(stranger), account.name))
    assert_not_found(request(token(stranger), "missing-account"))
  end

  test "user and organization flags independently hide the context", %{user: user, account: account} do
    stub(FeatureFlags, :luft_enabled?, fn _ -> false end)
    assert_not_found(request(token(user), account.name))
    assert_not_found(request(token(user), user.account.name))

    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> false end)
    assert_not_found(request(token(user), account.name))
  end

  test "inactive and disabled users cannot use a stale authenticated snapshot", %{user: user, account: account} do
    stub(Authentication, :app_user, fn _ -> user end)
    Repo.update!(Ecto.Changeset.change(user, active: false))
    assert user |> token() |> request(account.name) |> json_response(401)
    assert_not_found(LuftContextController.show(build_conn(), %{"account_handle" => account.name}))

    Repo.update!(Ecto.Changeset.change(user, active: true, disabled_at: DateTime.utc_now(:second)))
    assert_not_found(LuftContextController.show(build_conn(), %{"account_handle" => account.name}))
  end

  test "deleted users cannot use a stale authenticated snapshot", %{user: user, account: account} do
    stub(Authentication, :app_user, fn _ -> user end)
    # Call the controller directly: authentication's independent user lookup may
    # already reject a JWT whose subject was deleted.
    Repo.delete!(user)
    conn = LuftContextController.show(build_conn(), %{"account_handle" => account.name})
    assert_not_found(conn)
  end

  test "role changes and removed membership override stale authentication roles", %{
    user: user,
    organization: organization,
    account: account
  } do
    stale_user = Accounts.put_organization_roles(user)
    stub(Authentication, :app_user, fn _ -> stale_user end)

    Accounts.update_user_role_in_organization(user, organization, :user)
    assert %{"can_create_threads" => false} = user |> token() |> request(account.name) |> json_response(200)

    Accounts.remove_user_from_organization(user, organization)
    assert_not_found(request(token(user), account.name))
  end

  test "people omit inactive, disabled and removed members", %{
    user: user,
    member: member,
    organization: organization,
    account: account
  } do
    inactive = AccountsFixtures.user_fixture()
    disabled = AccountsFixtures.user_fixture()
    for person <- [inactive, disabled], do: Accounts.add_user_to_organization(person, organization, role: :user)
    Repo.update!(Ecto.Changeset.change(inactive, active: false))
    Repo.update!(Ecto.Changeset.change(disabled, disabled_at: DateTime.utc_now(:second)))
    Accounts.remove_user_from_organization(member, organization)

    assert %{"people" => people} = user |> token() |> request(account.name) |> json_response(200)
    assert people == [person(user)]
  end

  test "authentication follows the API's 401 and non-user 403 conventions", %{account: account} do
    assert nil |> request(account.name) |> json_response(401)
    assert "invalid" |> request(account.name) |> json_response(401)

    {:ok, {_account_token, bearer}} =
      Accounts.create_account_token(%{
        account: account,
        name: "luft-context",
        scopes: ["project:cache:read"],
        all_projects: true
      })

    assert bearer |> request(account.name) |> json_response(403)
  end

  defp request(token, handle) do
    conn = build_conn()
    conn = if token, do: put_req_header(conn, "authorization", "Bearer #{token}"), else: conn
    get(conn, "/api/accounts/#{handle}/luft-context")
  end

  defp assert_not_found(conn) do
    assert json_response(conn, 404) == %{"message" => "Not found."}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  defp person(user), do: %{"id" => user.id, "handle" => user.account.name, "active" => true}

  defp token(user) do
    {:ok, token, _} = Tuist.Guardian.encode_and_sign(user, %{}, token_type: "access_token")
    token
  end
end
