defmodule TuistWeb.EntirePluginControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Entire.Client, as: Entire
  alias Tuist.Entire.Installation
  alias Tuist.EntireTrails
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :register_and_log_in_user

  setup do
    stub(EntireTrails, :enabled?, fn _ -> true end)
    stub(Entire, :config, fn -> [slug: "tuist"] end)
    :ok
  end

  test "installs for Trail insights without enabling CI and consumes callback state once", %{conn: conn, user: user} do
    started = get(conn, ~p"/integrations/entire/start?#{%{account_handle: user.account.name}}")
    destination = URI.parse(redirected_to(started))
    assert destination.host == "entire.com"
    assert destination.path == "/plugins/tuist/install"
    %{state: state} = get_session(started, :entire_install)
    assert URI.decode_query(destination.query)["state"] == state

    stub(Entire, :verify_receipt, fn "receipt", ^state ->
      {:ok, %{"installation_id" => "ins_controller"}}
    end)

    callback = get(recycle(started), ~p"/integrations/entire/callback?#{%{state: state, receipt: "receipt"}}")
    assert redirected_to(callback) == ~p"/#{user.account.name}/settings/integrations"
    assert Repo.get_by!(Installation, remote_id: "ins_controller").account_id == user.account.id
    assert get_session(callback, :entire_install) == nil

    replayed = get(recycle(started), ~p"/integrations/entire/callback?#{%{state: state, receipt: "receipt"}}")
    assert json_response(replayed, 400)["error"] == "Invalid or expired Entire installation"
  end

  test "rejects callbacks from another browser or with mismatched state", %{conn: conn, user: user} do
    started = get(conn, ~p"/integrations/entire/start?#{%{account_handle: user.account.name}}")
    %{state: state} = get_session(started, :entire_install)

    assert json_response(get(conn, ~p"/integrations/entire/callback?#{%{state: state, receipt: "receipt"}}"), 400)

    assert json_response(
             get(recycle(started), ~p"/integrations/entire/callback?#{%{state: "wrong", receipt: "receipt"}}"),
             400
           )

    assert Repo.aggregate(Installation, :count) == 0
  end

  test "rejects installation for an account the user cannot manage", %{conn: conn} do
    other = AccountsFixtures.user_fixture()
    assert json_response(get(conn, ~p"/integrations/entire/start?#{%{account_handle: other.account.name}}"), 403)
  end

  test "rejects installation when Trail insights are disabled", %{conn: conn, user: user} do
    stub(EntireTrails, :enabled?, fn _ -> false end)
    assert json_response(get(conn, ~p"/integrations/entire/start?#{%{account_handle: user.account.name}}"), 403)
  end
end
