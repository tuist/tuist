defmodule TuistWeb.OpsAccountKuraDeploymentLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    conn = log_in_user(conn, user)

    stub(Accounts, :tuist_operator?, fn _ -> true end)

    %{conn: conn, user: user}
  end

  test "renders a scoped Kura deployment detail page with Grafana logs", %{conn: conn, user: user} do
    stub(Environment, :prod?, fn -> true end)

    {:ok, server} =
      Kura.create_server(%{
        account_id: user.account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}/kura/deployments/#{deployment.id}")

    assert html =~ "Kura deployment"
    assert html =~ "0.5.2"
    refute html =~ "kura@0.5.2"

    [href] = html |> Floki.parse_document!() |> Floki.attribute("a[href^='https://tuist.grafana.net/explore']", "href")
    left = href |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("left") |> JSON.decode!()
    [query] = left["queries"]

    assert left["datasource"] == "pulse-sql"
    assert query["rawSql"] =~ "'^#{server.provisioner_node_ref}-[0-9]+$'"
  end

  test "hides the logs link outside production", %{conn: conn, user: user} do
    stub(Environment, :prod?, fn -> false end)

    {:ok, server} =
      Kura.create_server(%{
        account_id: user.account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)

    {:ok, _lv, html} = live(conn, ~p"/ops/accounts/#{user.account.id}/kura/deployments/#{deployment.id}")

    refute html =~ "Kubernetes logs"
  end

  test "renders a superseded deployment", %{conn: conn, user: user} do
    {:ok, server} =
      Kura.create_server(%{
        account_id: user.account.id,
        region: "local-controller",
        image_tag: "0.5.2"
      })

    deployment = List.first(server.deployments)
    {:ok, deployment} = Kura.mark_superseded(deployment, "superseded by Kura image 0.5.3")

    {:ok, _live_view, html} =
      live(conn, ~p"/ops/accounts/#{user.account.id}/kura/deployments/#{deployment.id}")

    assert html =~ "Superseded"
    assert html =~ "superseded by Kura image 0.5.3"
  end
end
