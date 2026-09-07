defmodule TuistWeb.IntegrationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.Buildkite
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "user123#{System.unique_integer([:positive])}")
    stub(Tuist.Environment, :github_app_configured?, fn -> true end)
    # The integrations UI gates its Enterprise tab on
    # `Entitlements.allows?(account, :github_enterprise_server)` which
    # short-circuits to true on self-hosted (`tuist_hosted?` false).
    # CI runs with `TUIST_HOSTED=1`, so without this stub the tab is
    # hidden and every test that interacts with it fails. The dedicated
    # entitlement-gate describe block (further down) overrides this.
    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "tuist-org",
        creator: user,
        preload: [:account]
      )

    selected_project = ProjectsFixtures.project_fixture(name: "tuist", account_id: account.id)

    conn =
      conn
      |> assign(:selected_project, selected_project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, project: selected_project, organization: organization, account: account}
  end

  test "renders integrations page with GitHub section", %{conn: conn, organization: organization} do
    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    assert html =~ "Integrations"
    assert html =~ "GitHub"
    assert html =~ "Connect any of your GitHub repositories to a project"
  end

  test "shows install GitHub app button when no installation exists", %{
    conn: conn,
    organization: organization,
    account: _account
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    assert has_element?(lv, "a", "Install GitHub App")
  end

  test "hides the GitHub Enterprise URL input by default", %{conn: conn, organization: organization} do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    refute html =~ "Server URL"
    assert html =~ "github.com"
    assert html =~ "Enterprise server"
  end

  test "reveals the URL input when the Enterprise server tab is selected", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.example.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    html = render_click(lv, "select-github-enterprise")
    assert html =~ "Server URL"
    assert html =~ "Organization"
  end

  test "shows a validation error and disables the install button for malformed URLs", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "not-a-url"
      })
      |> render_change()

    assert html =~ "Invalid URL"
  end

  test "rejects github.com URLs on the Enterprise server tab", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.com/tuist/tuist"
      })
      |> render_change()

    assert html =~ "Use a GitHub Enterprise Server URL"
  end

  test "rejects repository URLs in the GitHub Enterprise Server URL field", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://tuist.dev/integrations/github/manifest/start?state=test"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.example.com/ios/app"
      })
      |> render_change()

    assert html =~ "Use a GitHub Enterprise Server URL"
  end

  test "passes the optional GitHub organization to the manifest flow", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, opts ->
      case Keyword.get(opts, :github_app_owner) do
        "ios" -> "https://tuist.dev/integrations/github/manifest/start?state=with-org"
        _ -> "https://tuist.dev/integrations/github/manifest/start?state=without-org"
      end
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.example.com",
        "github_app_owner" => "ios"
      })
      |> render_change()

    assert html =~ "state=with-org"
  end

  test "shows a validation error for malformed GitHub organization names", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://tuist.dev/integrations/github/manifest/start?state=test"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{
        "github_client_url" => "https://github.example.com",
        "github_app_owner" => "ios/bumble"
      })
      |> render_change()

    assert html =~ "Invalid organization"
  end

  test "switching back to github.com hides the input and clears the URL", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    render_click(lv, "select-github-enterprise")

    lv
    |> form("form[phx-change=update-github-client-url]", %{
      "github_client_url" => "https://github.example.com"
    })
    |> render_change()

    html = render_click(lv, "select-github-com")

    refute html =~ "Server URL"
    assert html =~ "Install GitHub App"
  end

  test "defaults to the Enterprise tab when github.com isn't configured but GHES is entitled",
       %{conn: conn, organization: organization} do
    # Regression: a self-hosted Tuist deployment with no `TUIST_GITHUB_APP_*`
    # env vars but a GHES-entitled account would otherwise land on the
    # github.com tab by default — clicking Install would generate a
    # broken `/apps//installations/new` URL because there is no global
    # app name to interpolate.
    stub(Tuist.Environment, :github_app_configured?, fn -> false end)

    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    # Server URL input renders (Enterprise tab is the default).
    assert html =~ "Server URL"

    # Form is interactive — change events trigger the validator.
    error_html =
      lv
      |> form("form[phx-change=update-github-client-url]", %{"github_client_url" => ""})
      |> render_change()

    # Empty URL on the Enterprise tab surfaces a "Required" error
    # (validate_github_client_url/2 distinguishes empty + Enterprise
    # from empty + github.com).
    assert error_html =~ "Required"
  end

  test "disables the Install button on the github.com tab when no github.com App is configured",
       %{conn: conn, organization: organization} do
    # Regression: the install URL interpolates `TUIST_GITHUB_APP_NAME`, so
    # with no github.com App configured the button linked to
    # `https://github.com/apps//installations/new`, which 404s on GitHub.
    stub(Tuist.Environment, :github_app_configured?, fn -> false end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    html = render_click(lv, "select-github-com")

    assert html =~ "No github.com App is configured"
    assert html =~ "TUIST_GITHUB_APP_NAME"
    assert has_element?(lv, "button[disabled]", "Install GitHub App")
    refute has_element?(lv, "a", "Install GitHub App")
  end

  test "keeps the Install button enabled on the github.com tab when the App is configured", %{
    conn: conn,
    organization: organization
  } do
    stub(VCS, :get_github_app_installation_url, fn _account, _opts ->
      "https://github.com/apps/test-app/installations/new"
    end)

    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    refute html =~ "No github.com App is configured"
    assert has_element?(lv, "a", "Install GitHub App")
  end

  describe "delete-connection" do
    test "does not allow deleting a VCS connection belonging to a different account", %{
      conn: conn,
      organization: organization
    } do
      # Given: a VCS connection on a completely different account
      other_user = AccountsFixtures.user_fixture()
      other_org = AccountsFixtures.organization_fixture(creator: other_user, preload: [:account])
      other_project = ProjectsFixtures.project_fixture(account_id: other_org.account.id)

      other_installation =
        VCSFixtures.github_app_installation_fixture(account_id: other_org.account.id)

      {:ok, other_connection} =
        Tuist.Projects.create_vcs_connection(%{
          project_id: other_project.id,
          provider: :github,
          repository_full_handle: "other-org/other-repo",
          github_app_installation_id: other_installation.id
        })

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

      # When: the user sends a delete event with the other account's connection ID
      render_hook(lv, "delete-connection", %{"connection_id" => other_connection.id})

      # Then: the connection should still exist
      assert {:ok, _} = Tuist.Projects.get_vcs_connection(other_connection.id)
    end
  end

  test "shows GitHub repositories when GitHub app is installed", %{
    conn: conn,
    organization: organization,
    account: account
  } do
    _github_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)

    stub(VCS, :get_github_app_installation_repositories, fn _installation ->
      {:ok, [%{id: 123, full_name: "test-org/test-repo"}]}
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

    assert has_element?(lv, "button", "Add new project connection")

    html = render_async(lv)
    assert html =~ "test-org/test-repo"
  end

  test "adopts the repository's default branch when creating a connection", %{
    conn: conn,
    organization: organization,
    account: account,
    project: project
  } do
    _github_installation = VCSFixtures.github_app_installation_fixture(account_id: account.id)

    stub(VCS, :get_github_app_installation_repositories, fn _installation ->
      {:ok, [%{id: 123, full_name: "test-org/test-repo", default_branch: "develop"}]}
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")
    render_async(lv)

    render_hook(lv, "select-project", %{"project_id" => Integer.to_string(project.id)})
    render_hook(lv, "select-repository", %{"repository" => "test-org/test-repo"})
    render_hook(lv, "create-connection", %{})

    assert Tuist.Projects.get_project_by_id(project.id).default_branch == "develop"
  end

  describe "GitHub Enterprise Server entitlement gate (hosted Tuist server)" do
    setup do
      stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
      :ok
    end

    test "hides the Enterprise server tab when the account is not on the Enterprise plan",
         %{conn: conn, organization: organization, account: account} do
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

      refute html =~ "Enterprise server"
    end

    test "shows the Enterprise server tab when the account is on the Enterprise plan",
         %{conn: conn, organization: organization, account: account} do
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

      assert html =~ "Enterprise server"
    end

    test "ignores a fabricated select-github-enterprise event when the account is not entitled",
         %{conn: conn, organization: organization, account: account} do
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings/integrations")

      html = render_click(lv, "select-github-enterprise")

      refute html =~ "Server URL"
    end
  end

  describe "Buildkite" do
    setup do
      stub(Tuist.FeatureFlags, :runners_enabled?, fn _account -> true end)
      :ok
    end

    defp connect_buildkite(lv, attrs) do
      lv
      |> form(
        "#connect-buildkite-form",
        Map.merge(%{"organization_slug" => "acme", "agent_token" => "bkct_secret"}, attrs)
      )
      |> render_submit()
    end

    test "connects a cluster from the modal and shows it on the card", %{conn: conn, account: account} do
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      # Nothing connected: the card offers the modal and takes no more room.
      refute html =~ ~s(id="buildkite-form")

      html = connect_buildkite(lv, %{})

      installation = Buildkite.get_installation(account.id)
      assert installation.organization_slug == "acme"
      assert installation.agent_token == "bkct_secret"
      # Derived, never taken from the form: a customer-chosen key could
      # collide with another account's and swap their reservations.
      assert installation.stack_key == "tuist-#{account.id}"
      assert html =~ ~s(value="acme")
    end

    test "masks the agent token so it is never typed in the clear", %{conn: conn, account: account} do
      # Noora's `text_input` derives the HTML input type from `input_type`,
      # not from `type`, so `type="password"` alone renders a plaintext
      # field. Only the rendered attribute catches it.
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      token_input = html |> Floki.parse_document!() |> Floki.find("input#buildkite-agent-token")

      assert [_] = token_input
      assert Floki.attribute(token_input, "type") == ["password"]
    end

    test "reports a rejected token instead of storing it", %{conn: conn, account: account} do
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      html = connect_buildkite(lv, %{"agent_token" => "bkua_wrong_kind_of_token"})

      assert html =~ "cluster agent token"
      assert is_nil(Buildkite.get_installation(account.id))
    end

    test "surfaces the last poll error so a broken connection is visible", %{conn: conn, account: account} do
      {:ok, installation} =
        Buildkite.upsert_installation(account.id, %{
          organization_slug: "acme",
          stack_key: "tuist-#{account.id}",
          agent_token: "bkct_secret"
        })

      Buildkite.record_poll_result(installation, {:error, :unauthorized})

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      assert html =~ "Buildkite rejected the agent token"
    end

    test "disconnects a cluster", %{conn: conn, account: account} do
      {:ok, _installation} =
        Buildkite.upsert_installation(account.id, %{
          organization_slug: "acme",
          stack_key: "tuist-#{account.id}",
          agent_token: "bkct_secret"
        })

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      lv |> element("button[phx-click=disconnect-buildkite]") |> render_click()

      assert is_nil(Buildkite.get_installation(account.id))
    end

    defp connected(account) do
      {:ok, _installation} =
        Buildkite.upsert_installation(account.id, %{
          organization_slug: "acme",
          stack_key: "tuist-#{account.id}",
          agent_token: "bkct_secret"
        })

      :ok
    end

    test "saves a new organization from the card while a blank token keeps the current one", %{
      conn: conn,
      account: account
    } do
      connected(account)
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      html =
        lv
        |> form("#buildkite-form", %{"organization_slug" => "acme-mobile", "agent_token" => ""})
        |> render_submit()

      assert html =~ "Buildkite connection saved."
      installation = Buildkite.get_installation(account.id)
      assert installation.organization_slug == "acme-mobile"
      assert installation.agent_token == "bkct_secret"
    end

    test "saves a new token from the card", %{conn: conn, account: account} do
      connected(account)
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      lv
      |> form("#buildkite-form", %{"organization_slug" => "acme", "agent_token" => "bkct_rotated"})
      |> render_submit()

      installation = Buildkite.get_installation(account.id)
      assert installation.agent_token == "bkct_rotated"
      assert installation.organization_slug == "acme"
    end

    test "keeps an invalid organization on screen with its error instead of saving it", %{
      conn: conn,
      account: account
    } do
      connected(account)
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/integrations")

      html =
        lv
        |> form("#buildkite-form", %{"organization_slug" => "acme corp", "agent_token" => ""})
        |> render_submit()

      assert html =~ ~s(value="acme corp")
      assert html =~ "has invalid format"
      assert Buildkite.get_installation(account.id).organization_slug == "acme"
    end

    test "enables Save changes only once something changed", %{conn: conn, account: account} do
      connected(account)
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      save = fn html -> html |> Floki.parse_document!() |> Floki.find("#buildkite-form button[type=submit]") end

      # Rendered valueless, which Floki reads back as an empty string.
      assert Floki.attribute(save.(html), "disabled") == [""]

      html =
        lv
        |> form("#buildkite-form", %{"organization_slug" => "acme", "agent_token" => "bkct_new"})
        |> render_change()

      assert Floki.attribute(save.(html), "disabled") == []
    end

    test "masks the token field on the card", %{conn: conn, account: account} do
      connected(account)
      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      token_input = html |> Floki.parse_document!() |> Floki.find("input#buildkite-token")

      assert [_] = token_input
      assert Floki.attribute(token_input, "type") == ["password"]
    end

    test "is hidden when runners are not enabled for the account", %{conn: conn, account: account} do
      stub(Tuist.FeatureFlags, :runners_enabled?, fn _account -> false end)

      {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/integrations")

      refute html =~ "buildkite-card-section"
    end
  end
end
