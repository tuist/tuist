defmodule TuistWeb.RunnerBuildkiteLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.FeatureFlags
  alias Tuist.Runners.Buildkite

  setup %{conn: conn} do
    stub(FeatureFlags, :runners_enabled?, fn _account -> true end)

    user = user_fixture()
    %{account: account} = organization_fixture(creator: user, preload: [:account])

    %{conn: log_in_user(conn, user), account: account, user: user}
  end

  test "connects a cluster and shows it afterwards", %{conn: conn, account: account} do
    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/buildkite")

    assert html =~ "Buildkite"

    lv
    |> form("[data-part=buildkite-form]", %{
      "organization_slug" => "acme",
      "cluster_name" => "macOS",
      "agent_token" => "bkct_secret"
    })
    |> render_submit()

    installation = Buildkite.get_installation(account.id)
    assert installation.organization_slug == "acme"
    assert installation.agent_token == "bkct_secret"
    # Derived, never taken from the form: a customer-chosen key could
    # collide with another account's and swap their reservations.
    assert installation.stack_key == "tuist-#{account.id}"
  end

  test "reports a rejected token instead of storing it", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/buildkite")

    html =
      lv
      |> form("[data-part=buildkite-form]", %{
        "organization_slug" => "acme",
        "agent_token" => "bkua_wrong_kind_of_token"
      })
      |> render_submit()

    assert html =~ "cluster agent token"
    assert is_nil(Buildkite.get_installation(account.id))
  end

  test "surfaces the last poll error so a broken connection is visible", %{
    conn: conn,
    account: account
  } do
    {:ok, installation} =
      Buildkite.upsert_installation(account.id, %{
        organization_slug: "acme",
        stack_key: "tuist-#{account.id}",
        agent_token: "bkct_secret"
      })

    Buildkite.record_poll_result(installation, {:error, :unauthorized})

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/buildkite")

    assert html =~ "Buildkite rejected the agent token"
  end

  test "disconnects a cluster", %{conn: conn, account: account} do
    {:ok, _installation} =
      Buildkite.upsert_installation(account.id, %{
        organization_slug: "acme",
        stack_key: "tuist-#{account.id}",
        agent_token: "bkct_secret"
      })

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/buildkite")

    lv |> element("button[phx-click=disconnect]") |> render_click()

    assert is_nil(Buildkite.get_installation(account.id))
  end

  test "lists the queue keys a pipeline can target", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/buildkite")

    # The queue key IS the profile's dispatch label, which is what makes
    # Buildkite routing reuse the GitHub lane's profile resolution.
    for profile <- Tuist.Runners.Profiles.list_for_account(account) do
      assert html =~ Tuist.Runners.Profile.dispatch_label(profile)
    end
  end

  test "is not reachable when runners are disabled", %{conn: conn, account: account} do
    stub(FeatureFlags, :runners_enabled?, fn _account -> false end)

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/runners/buildkite")
    end
  end
end
