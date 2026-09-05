defmodule TuistWeb.RunnerSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Phoenix.LiveViewTest
  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.VCSFixtures

  alias Tuist.Accounts.Account
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.Buildkite

  setup %{conn: conn} do
    stub(FeatureFlags, :runners_enabled?, fn _account -> true end)

    user = user_fixture()
    %{account: account} = organization_fixture(creator: user, preload: [:account])

    %{conn: log_in_user(conn, user), account: account, user: user}
  end

  test "appears as a tab on the settings pages", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    assert html =~ ~p"/#{account.name}/settings/runners"
  end

  test "hides the tab when runners are disabled", %{conn: conn, account: account} do
    stub(FeatureFlags, :runners_enabled?, fn _account -> false end)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings")

    refute html =~ ~p"/#{account.name}/settings/runners"
  end

  test "shows GitHub Actions as connected once the GitHub App is installed", %{
    conn: conn,
    account: account
  } do
    github_app_installation_fixture(account_id: account.id)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/runners")

    assert html =~ ~s(data-status="connected")
  end

  test "shows GitHub Actions as not connected while the App install is still pending", %{
    conn: conn,
    account: account
  } do
    # A manifest-flow row exists before GitHub assigns an installation id:
    # the App is registered (it has a private key) but not yet installed.
    # No webhook can arrive for it, so it must not read as connected.
    github_app_installation_fixture(
      account_id: account.id,
      installation_id: nil,
      private_key: "-----BEGIN RSA PRIVATE KEY-----"
    )

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/runners")

    assert html =~ ~s(data-status="disconnected")
  end

  test "masks the agent token so it is never typed in the clear", %{conn: conn, account: account} do
    # Noora's `text_input` derives the HTML input type from `input_type`,
    # not from `type`, so `type="password"` on its own silently renders a
    # plaintext field. That is invisible in review and in every assertion
    # about behaviour — only the rendered attribute catches it.
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/runners")
    html = open_buildkite(lv)

    token_input =
      html
      |> Floki.parse_document!()
      |> Floki.find("input#buildkite-agent-token")

    assert [_] = token_input
    assert Floki.attribute(token_input, "type") == ["password"]
  end

  test "connects a cluster and shows it afterwards", %{conn: conn, account: account} do
    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/runners")
    html = open_buildkite(lv)

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
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/runners")
    html = open_buildkite(lv)

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

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/runners")

    assert html =~ "Buildkite rejected the agent token"
  end

  test "disconnects a cluster", %{conn: conn, account: account} do
    {:ok, _installation} =
      Buildkite.upsert_installation(account.id, %{
        organization_slug: "acme",
        stack_key: "tuist-#{account.id}",
        agent_token: "bkct_secret"
      })

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/runners")

    lv |> element("button[phx-click=disconnect]") |> render_click()

    assert is_nil(Buildkite.get_installation(account.id))
  end

  test "lists the queue keys a pipeline can target", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/runners")
    html = open_buildkite(lv)

    # The queue key IS the profile's dispatch label, which is what makes
    # Buildkite routing reuse the GitHub lane's profile resolution.
    for profile <- Tuist.Runners.Profiles.list_for_account(account) do
      assert html =~ Tuist.Runners.Profile.dispatch_label(profile)
    end
  end

  test "is not reachable when runners are disabled", %{conn: conn, account: account} do
    stub(FeatureFlags, :runners_enabled?, fn _account -> false end)

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/settings/runners")
    end
  end

  test "hides the Buildkite form until the provider is switched on", %{conn: conn, account: account} do
    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/runners")

    refute html =~ "buildkite-form"
    assert open_buildkite(lv) =~ "buildkite-form"
  end

  test "switching Buildkite off keeps the connection but stops polling", %{conn: conn, account: account} do
    {:ok, _installation} =
      Buildkite.upsert_installation(account.id, %{
        organization_slug: "acme",
        stack_key: "tuist-#{account.id}",
        agent_token: "bkct_secret"
      })

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/runners")
    assert html =~ "buildkite-form"

    html = lv |> element("#buildkite-toggle-true") |> render_click()

    refute html =~ "buildkite-form"
    installation = Buildkite.get_installation(account.id)
    assert installation.organization_slug == "acme"
    refute installation.enabled
    refute Enum.any?(Buildkite.list_pollable_installations(), &(&1.account_id == account.id))
  end

  test "switching GitHub Actions off persists to the account", %{conn: conn, account: account} do
    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/runners")
    assert html =~ "Manage in Integrations"

    html = lv |> element("#github-actions-toggle-true") |> render_click()

    refute html =~ "Manage in Integrations"
    refute Repo.get!(Account, account.id).runner_github_actions_enabled
  end

  test "the old dedicated page is gone", %{conn: conn, account: account} do
    # The endpoint renders a router miss as a 404 page rather than
    # re-raising, so this is what a stale bookmark or docs link actually
    # gets back.
    conn = get(conn, ~p"/#{account.name}/runners/buildkite")

    assert response(conn, 404)
  end

  defp open_buildkite(lv), do: lv |> element("#buildkite-toggle-false") |> render_click()
end
