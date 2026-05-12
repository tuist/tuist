defmodule TuistWeb.OpsAccountKuraDeploymentLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Environment
  alias Tuist.Kura
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)

    stub(Environment, :ops_user_handles, fn -> [user.account.name] end)

    %{conn: conn, user: user}
  end

  test "renders a scoped Kura deployment detail page with Grafana logs", %{conn: conn, user: user} do
    {:ok, server} =
      Kura.create_server(%{
        account_id: user.account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}/kura/deployments/#{deployment.id}")

    assert html =~ "Kura deployment"
    assert html =~ "kura@0.5.2"
    assert html =~ "Grafana"
    assert html =~ "tuist.grafana.net/explore"
  end
end
