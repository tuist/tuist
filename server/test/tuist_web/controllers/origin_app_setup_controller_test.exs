defmodule TuistWeb.OriginAppSetupControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Origin
  alias Tuist.Origin.Client
  alias Tuist.Origin.Signatures
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.BadRequestError
  alias TuistWeb.OriginAppSetupController

  setup do
    user = AccountsFixtures.user_fixture()
    stub(Client, :configured?, fn -> true end)
    stub(Environment, :origin_app_id, fn -> "app_tuist" end)
    %{user: user, account: user.account, conn: authenticated_conn(user)}
  end

  test "starts consent with browser-bound state and minimum scopes", %{
    conn: conn,
    account: account,
    user: user
  } do
    conn = OriginAppSetupController.start(conn, %{"account_id" => to_string(account.id)})
    query = conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    session = get_session(conn, :origin_installation)
    assert query["client_id"] == "app_tuist"
    assert query["scope"] == Enum.join(Client.scopes(), " ")
    assert query["state"] == session.state
    assert String.ends_with?(query["redirect_uri"], "/integrations/origin/setup")
    assert session.account_id == account.id
    assert session.user_id == user.id
  end

  test "a different signed-in user cannot reuse browser installation state", %{
    conn: conn,
    account: account
  } do
    conn = OriginAppSetupController.start(conn, %{"account_id" => to_string(account.id)})
    conn = browser_request(conn, AccountsFixtures.user_fixture())
    reject(&Signatures.verify_receipt/2)
    reject(&Client.get_installation/1)

    assert_raise BadRequestError, fn ->
      OriginAppSetupController.setup(conn, %{"installation_receipt" => "receipt"})
    end
  end

  test "a valid same-user callback attaches the installation and consumes state", %{
    conn: conn,
    account: account,
    user: user
  } do
    conn =
      conn
      |> OriginAppSetupController.start(%{"account_id" => to_string(account.id)})
      |> browser_request(user)

    session = get_session(conn, :origin_installation)

    conn =
      put_session(conn, :origin_installation, %{
        session
        | issued_at: System.system_time(:second) + 30
      })

    state = session.state

    expect(Signatures, :verify_receipt, fn "receipt", ^state ->
      {:ok, %{"sub" => "i_verified", "namespace_id" => "ns_test"}}
    end)

    expect(Client, :get_installation, fn "i_verified" ->
      {:ok,
       %{
         "id" => "i_verified",
         "appId" => "app_tuist",
         "target" => %{"id" => "ns_test"},
         "scopes" => Client.scopes()
       }}
    end)

    conn =
      OriginAppSetupController.setup(conn, %{
        "installation_receipt" => "receipt",
        "installation_id" => "i_attacker"
      })

    assert redirected_to(conn) == "/#{account.name}/settings/integrations"
    assert get_session(conn, :origin_installation) == nil
    assert [%{installation_id: "i_verified"}] = Origin.list_installations(account.id)
  end

  test "missing, expired, and invalid receipt state is rejected", %{
    conn: conn,
    account: account,
    user: user
  } do
    assert_raise BadRequestError, fn ->
      OriginAppSetupController.setup(conn, %{"installation_receipt" => "receipt"})
    end

    started =
      conn
      |> OriginAppSetupController.start(%{"account_id" => to_string(account.id)})
      |> browser_request(user)

    session = get_session(started, :origin_installation)

    expired =
      put_session(started, :origin_installation, %{
        session
        | issued_at: System.system_time(:second) - 601
      })

    assert_raise BadRequestError, fn ->
      OriginAppSetupController.setup(expired, %{"installation_receipt" => "receipt"})
    end

    stub(Signatures, :verify_receipt, fn _, _ -> {:error, :invalid_origin_receipt} end)

    assert_raise BadRequestError, fn ->
      OriginAppSetupController.setup(started, %{"installation_receipt" => "receipt"})
    end
  end

  test "starting consent requires account ownership and a valid account ID", %{conn: conn} do
    other = AccountsFixtures.user_fixture()

    assert_raise BadRequestError, fn ->
      OriginAppSetupController.start(conn, %{"account_id" => to_string(other.account.id)})
    end

    assert_raise BadRequestError, fn ->
      OriginAppSetupController.start(conn, %{"account_id" => "not-an-id"})
    end

    assert_raise BadRequestError, fn ->
      build_conn()
      |> init_test_session(%{})
      |> OriginAppSetupController.start(%{
        "account_id" => to_string(other.account.id)
      })
    end
  end

  defp browser_request(conn, user) do
    user
    |> authenticated_conn()
    |> put_session(:origin_installation, get_session(conn, :origin_installation))
  end

  defp authenticated_conn(user) do
    build_conn() |> init_test_session(%{}) |> Authentication.put_current_user(user)
  end
end
