defmodule TuistWeb.AccountWorkloadIdentitiesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Phoenix.LiveView.Socket
  alias Tuist.Accounts
  alias Tuist.Authorization
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.AuthenticationSettingsLive
  alias TuistWeb.Components.WorkloadIdentities
  alias TuistWeb.Errors.UnauthorizedError

  @params %{
    "name" => "Production workload",
    "issuer" => "https://oidc.fly.io/example-org",
    "jwks_url" => "https://oidc.fly.io/example-org/.well-known/jwks",
    "audience" => "tuist",
    "claims" => ~s({"org_id":"123","app_id":"456"})
  }

  setup %{organization: organization} do
    %{account: organization.account, params: @params}
  end

  defp path(account), do: ~p"/#{account.name}/settings/authentication"

  defp open(%{conn: conn, account: account}) do
    {:ok, lv, _} = live(conn, path(account))
    render_hook(lv, "toggle_oidc_configuration", %{"checked" => true})
    lv
  end

  defp submit(lv, params), do: lv |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => params}) |> render_submit()
  defp select_template(lv, template), do: render_hook(lv, "select_oidc_template", %{"value" => [template]})

  defp fill_fly(lv, overrides \\ %{}) do
    values =
      Map.merge(%{"organization_slug" => "example-org", "organization_id" => "123", "application_id" => "456"}, overrides)

    lv |> form("#oidc-trust-policy-form", %{"fly_template" => values}) |> render_change()
  end

  test "starts compact with a presentation-only configuration switch", context do
    {:ok, lv, _} = live(context.conn, path(context.account))
    assert has_element?(lv, "#oidc-configuration-toggle:not([data-checked])[aria-expanded=false]", "Show configuration")
    assert has_element?(lv, "#oidc-configuration-toggle[aria-controls=oidc-trust-policy-form]")
    assert has_element?(lv, "#oidc-trust-policy-form[hidden]")
    assert has_element?(lv, "#oidc-trust-policies > [data-part=content][hidden]")

    render_hook(lv, "toggle_oidc_configuration", %{"checked" => true})
    assert has_element?(lv, "#oidc-configuration-toggle[data-checked][aria-expanded=true]")
    refute has_element?(lv, "#oidc-trust-policy-form[hidden]")
    refute has_element?(lv, "#oidc-trust-policies > [data-part=content][hidden]")
    assert [] = Accounts.list_oidc_trust_policies(context.account)
  end

  test "places the workload section below SCIM with the switch immediately before its title", context do
    lv = open(context)
    assert has_element?(lv, "#sso-form + [data-part=scim-card] + #account-workload-identities")

    assert has_element?(
             lv,
             "[data-part=heading] > #oidc-configuration-toggle + #oidc-workload-title",
             "Workload identities"
           )
  end

  test "hiding configuration retains malformed drafts and helper overrides", context do
    lv = open(context)
    select_template(lv, "fly")
    fill_fly(lv)
    params = Map.put(context.params, "claims", "{unfinished-workload-draft")
    lv |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => params}) |> render_change()
    render_hook(lv, "toggle_sso", %{})
    render_hook(lv, "select_provider", %{"value" => ["okta"]})

    for checked <- [false, true] do
      render_hook(lv, "toggle_oidc_configuration", %{"checked" => checked})
      assert has_element?(lv, "#oidc-trust-policy-claims", params["claims"])
      assert has_element?(lv, "#oidc-fly-organization-slug[value='example-org']")
      assert has_element?(lv, "#oidc-template-overrides")
      assert has_element?(lv, "[data-part=advanced][open]")
      assert has_element?(lv, "#sso-provider-select", "Okta")
    end

    submit(lv, params)
    refute has_element?(lv, "#oidc-trust-policy-form[hidden]")
    assert has_element?(lv, "#oidc-trust-policy-form", "Claims must be valid JSON.")
  end

  test "hiding the form leaves saved identities, grants, setup and removal available", context do
    lv = open(context)
    submit(lv, context.params)
    assert [policy] = Accounts.list_oidc_trust_policies(context.account)
    render_hook(lv, "toggle_oidc_configuration", %{"checked" => false})
    assert has_element?(lv, "#oidc-trust-policy-form[hidden]")
    refute has_element?(lv, "#oidc-trust-policies > [data-part=content][hidden]")
    assert has_element?(lv, "#oidc-trust-policy-#{policy.id}", policy.name)
    assert has_element?(lv, "#oidc-trust-policy-#{policy.id} [data-scope=account]", "all current and future projects")
    assert has_element?(lv, "#oidc-workload-setup", "tuist auth login")
    assert [^policy] = Accounts.list_oidc_trust_policies(context.account)

    {:ok, reloaded, _} = live(context.conn, path(context.account))
    assert has_element?(reloaded, "#oidc-trust-policy-form[hidden]")
    assert has_element?(reloaded, "#oidc-trust-policy-#{policy.id}")
    assert has_element?(reloaded, "#oidc-workload-setup")
    reloaded |> element("#oidc-trust-policy-#{policy.id} button") |> render_click()
    assert [] = Accounts.list_oidc_trust_policies(context.account)
    assert has_element?(reloaded, "#oidc-trust-policies > [data-part=content][hidden]")
  end

  test "ignores malformed visibility events without losing the current state", context do
    lv = open(context)

    for params <- [%{}, %{"checked" => "false"}, %{"checked" => nil}, %{"checked" => %{}}] do
      render_hook(lv, "toggle_oidc_configuration", params)
      refute has_element?(lv, "#oidc-trust-policy-form[hidden]")
    end
  end

  test "lives under account Authentication and defaults to manual account-wide configuration", context do
    lv = open(context)
    assert has_element?(lv, "#account-workload-identities")
    assert has_element?(lv, ".noora-tab-menu-horizontal-item[data-selected]", "Authentication")
    assert has_element?(lv, "[data-part=sso-card]")
    assert has_element?(lv, "[data-part=scim-card]")
    assert has_element?(lv, "#oidc-trust-policies", "Workload identities")
    refute has_element?(lv, ".noora-tab-menu-horizontal-item", "Workload identities")
    refute has_element?(lv, ".noora-tab-menu-horizontal-item", "Single Sign-On")
    assert has_element?(lv, "#oidc-template-select-custom", "Custom provider")
    assert has_element?(lv, "#oidc-trust-policy-claims-container[phx-hook=JSONInput]")
    assert has_element?(lv, "#oidc-trust-policy-claims[maxlength='8192']")
    refute has_element?(lv, "#oidc-projects")
    assert has_element?(lv, "[data-part=subtitle]", "all current and future projects in this account")
    refute has_element?(lv, "#oidc-workload-setup")
    assert page_title(lv) == "Authentication · #{context.account.name} · Tuist"
  end

  test "is part of account Authentication and absent from project settings", %{
    conn: conn,
    account: account,
    project: project
  } do
    {:ok, lv, _} = live(conn, ~p"/#{account.name}/settings/authentication")
    assert has_element?(lv, "#oidc-trust-policy-form")

    for tab <- ["", "/notifications", "/automations", "/bundles"] do
      {:ok, settings, _} = live(conn, "/#{account.name}/#{project.name}/settings#{tab}")
      refute has_element?(settings, "#oidc-trust-policy-form")
      refute has_element?(settings, "a[href='/#{account.name}/#{project.name}/settings/authentication']")
    end
  end

  test "old workload links redirect to the section on the single Authentication page", %{conn: conn, account: account} do
    assert {:error, {:live_redirect, %{to: destination}}} =
             live(conn, ~p"/#{account.name}/settings/authentication/workload-identities")

    assert destination == ~p"/#{account.name}/settings/authentication#oidc-trust-policies"
  end

  test "preserves independent SSO and workload drafts on the same page", context do
    lv = open(context)
    render_hook(lv, "toggle_sso", %{})
    render_hook(lv, "select_provider", %{"value" => ["okta"]})

    lv
    |> form("#oidc-trust-policy-form", %{
      "oidc_trust_policy" => Map.put(context.params, "claims", "{unfinished-workload-draft")
    })
    |> render_change()

    assert has_element?(lv, "#sso-provider-select", "Okta")
    render_hook(lv, "toggle_sso", %{})
    assert has_element?(lv, "#oidc-trust-policy-claims", "{unfinished-workload-draft")
    assert has_element?(lv, "input[name='oidc_trust_policy[name]'][value='Production workload']")
  end

  test "personal accounts can manage workload identities before creating projects and without SSO", %{
    conn: conn,
    user: user
  } do
    conn = assign(conn, :selected_account, user.account)
    {:ok, lv, _} = live(conn, path(user.account))
    assert has_element?(lv, "#oidc-trust-policy-form[hidden]")
    render_hook(lv, "toggle_oidc_configuration", %{"checked" => true})
    refute has_element?(lv, "#oidc-trust-policy-form[hidden]")
    refute has_element?(lv, "#oidc-projects")
    refute has_element?(lv, "#sso-form")
    submit(lv, @params)
    assert [%{account_id: id}] = Accounts.list_oidc_trust_policies(user.account)
    assert id == user.account.id
  end

  test "one account identity displays its account-wide scope and login instructions", context do
    lv = open(context)
    submit(lv, context.params)
    assert [policy] = Accounts.list_oidc_trust_policies(context.account)
    assert policy.account_id == context.account.id
    assert has_element?(lv, "#oidc-trust-policy-#{policy.id} [data-scope=account]", "all current and future projects")
    assert has_element?(lv, "#oidc-workload-setup", context.account.name)
    assert has_element?(lv, "#oidc-workload-setup", "tuist auth login")
    assert has_element?(lv, "#oidc-workload-setup", "mix tuist.login")
    lv |> element("#oidc-trust-policy-#{policy.id} button") |> render_click()
    assert [] = Accounts.list_oidc_trust_policies(context.account)
  end

  test "obsolete project and forged account parameters cannot change the owning account", context do
    foreign = ProjectsFixtures.project_fixture(preload: [:account])
    lv = open(context)
    attrs = Map.merge(context.params, %{"project_ids" => [to_string(foreign.id)], "account_id" => foreign.account_id})
    render_submit(lv, "create_oidc_trust_policy", %{"oidc_trust_policy" => attrs})
    assert [policy] = Accounts.list_oidc_trust_policies(context.account)
    assert policy.account_id == context.account.id
    assert [] = Accounts.list_oidc_trust_policies(foreign.account)
  end

  test "Fly template creates an account-wide identity with editable string-valued claims", context do
    lv = open(context)
    select_template(lv, "fly")
    fill_fly(lv)
    assert has_element?(lv, "[data-part=advanced]:not([open])")
    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/example-org']")
    lv |> form("#oidc-trust-policy-form") |> render_submit()
    assert [policy] = Accounts.list_oidc_trust_policies(context.account)
    assert policy.claims === %{"org_id" => "123", "app_id" => "456"}
    assert policy.account_id == context.account.id
    assert has_element?(lv, "#oidc-template-select-custom", "Custom provider")
    refute has_element?(lv, "#oidc-projects")
  end

  test "helper edits and queued stale events never restore obsolete generated identity values", context do
    lv = open(context)
    select_template(lv, "fly")
    fill_fly(lv)
    fill_fly(lv, %{"organization_slug" => "another-org", "application_id" => "789"})
    assert has_element?(lv, "#oidc-trust-policy-claims", ~s("app_id":"789"))

    render_change(lv, "change_oidc_trust_policy", %{
      "_target" => ["fly_template", "organization_slug"],
      "oidc_trust_policy" => Map.put(context.params, "name", "Fly.io Machines"),
      "fly_template" => %{"organization_slug" => "latest-org", "organization_id" => "123", "application_id" => "456"}
    })

    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/latest-org']")

    render_change(lv, "change_oidc_trust_policy", %{
      "_target" => ["oidc_trust_policy", "name"],
      "oidc_trust_policy" => Map.put(context.params, "name", "My deployment"),
      "fly_template" => %{"organization_slug" => "latest-org", "organization_id" => "123", "application_id" => "456"}
    })

    assert has_element?(lv, "#oidc_trust_policy_name[value='My deployment']")
    assert has_element?(lv, "#oidc_trust_policy_issuer[value='https://oidc.fly.io/latest-org']")
    fill_fly(lv, %{"organization_slug" => "", "application_id" => ""})
    lv |> form("#oidc-trust-policy-form") |> render_submit()
    assert [] = Accounts.list_oidc_trust_policies(context.account)
  end

  test "manual drafts survive template switches with visible overrides", context do
    lv = open(context)

    params = %{
      context.params
      | "issuer" => "https://custom.example",
        "jwks_url" => "https://custom.example/keys",
        "claims" => ~s({"sub":"deployment"})
    }

    lv |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => params}) |> render_change()
    select_template(lv, "fly")
    fill_fly(lv)
    select_template(lv, "custom")
    select_template(lv, "fly")
    assert has_element?(lv, "#oidc-template-overrides", "Your manual changes override this template.")
    assert has_element?(lv, "[data-part=advanced][open] #oidc-trust-policy-claims", params["claims"])
    lv |> form("#oidc-trust-policy-form") |> render_submit()
    assert [policy] = Accounts.list_oidc_trust_policies(context.account)
    assert policy.issuer == params["issuer"]
    assert policy.claims == %{"sub" => "deployment"}
  end

  test "matching helpers clear override warnings and visible name/audience edits do not warn", context do
    lv = open(context)
    select_template(lv, "fly")
    fill_fly(lv)

    lv
    |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => %{"issuer" => "https://oidc.fly.io/another-org"}})
    |> render_change()

    assert has_element?(lv, "#oidc-template-overrides")
    fill_fly(lv, %{"organization_slug" => "another-org"})
    refute has_element?(lv, "#oidc-template-overrides")

    lv
    |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => %{"name" => "Deployment", "audience" => "custom"}})
    |> render_change()

    refute has_element?(lv, "#oidc-template-overrides")
  end

  test "invalid helpers and unknown templates never create identities", context do
    lv = open(context)
    select_template(lv, "unknown")
    refute has_element?(lv, "#oidc-fly-template")
    select_template(lv, "fly")

    for invalid <- [
          %{"organization_slug" => "../another"},
          %{"organization_slug" => "org?query"},
          %{"organization_id" => "name"},
          %{"application_id" => "1.2"},
          %{"application_id" => String.duplicate("1", 256)}
        ] do
      fill_fly(lv, invalid)
      lv |> form("#oidc-trust-policy-form") |> render_submit()
      assert has_element?(lv, "#oidc-trust-policy-form", "Enter a valid Fly.io organization slug")
      assert [] = Accounts.list_oidc_trust_policies(context.account)
    end
  end

  test "malformed JSON preserves the draft and expands Advanced", context do
    lv = open(context)
    select_template(lv, "fly")
    fill_fly(lv)
    submit(lv, Map.put(context.params, "claims", ~s({"sub":"unfinished",})))
    assert has_element?(lv, "[data-part=advanced][open]", "Claims must be valid JSON.")
    assert has_element?(lv, "#oidc-trust-policy-claims", ~s({"sub":"unfinished",}))
    assert [] = Accounts.list_oidc_trust_policies(context.account)
  end

  test "JSON editing preserves scalar types and safely highlights changes", context do
    lv = open(context)
    params = Map.put(context.params, "claims", ~s({"project_id":42,"protected":true}))
    lv |> form("#oidc-trust-policy-form", %{"oidc_trust_policy" => params}) |> render_change()
    assert has_element?(lv, ".json-input .number", "42")
    assert has_element?(lv, ".json-input .boolean", "true")
    submit(lv, params)
    assert [%{claims: %{"project_id" => 42, "protected" => true}}] = Accounts.list_oidc_trust_policies(context.account)
  end

  test "rejects oversized, non-object, nested and reserved claims", context do
    lv = open(context)

    for claims <- [
          String.duplicate(" ", 8193),
          ~s(["sub"]),
          "null",
          "{}",
          ~s({"sub":["x"]}),
          ~s({"iss":"https://example.com"})
        ] do
      render_submit(lv, "create_oidc_trust_policy", %{"oidc_trust_policy" => Map.put(context.params, "claims", claims)})
      assert has_element?(lv, ".noora-text-area[data-error]")
      assert [] = Accounts.list_oidc_trust_policies(context.account)
    end
  end

  test "renders the account policy limit inline", context do
    for i <- 1..20 do
      Accounts.create_oidc_trust_policy(context.account, %{
        name: "Policy #{i}",
        issuer: @params["issuer"],
        jwks_url: @params["jwks_url"],
        claims: %{"sub" => "#{i}"}
      })
    end

    lv = open(context)
    submit(lv, context.params)
    assert has_element?(lv, "#oidc-trust-policy-form", "cannot exceed 20 trust policies per account")
    assert length(Accounts.list_oidc_trust_policies(context.account)) == 20
  end

  test "deletion cannot cross account boundaries and malformed IDs are harmless", context do
    foreign = ProjectsFixtures.project_fixture(preload: [:account])

    {:ok, policy} =
      Accounts.create_oidc_trust_policy(foreign.account, %{
        name: "Foreign",
        issuer: @params["issuer"],
        jwks_url: @params["jwks_url"],
        claims: %{"sub" => "foreign"}
      })

    lv = open(context)

    for id <- [to_string(policy.id), "not-an-id"] do
      render_click(lv, "delete_oidc_trust_policy", %{"policy-id" => id})
      assert has_element?(lv, "#oidc-trust-policy-form")
    end

    assert [%{id: id}] = Accounts.list_oidc_trust_policies(foreign.account)
    assert id == policy.id
  end

  test "requires account-update permission on mount and both mutations against a fresh account", context do
    socket = %Socket{assigns: %{selected_account: %{context.account | name: "stale"}, current_user: context.user}}

    expect(Authorization, :authorize, 3, fn :account_update, user, account ->
      assert user.id == context.user.id
      assert account.name == context.account.name
      {:error, :forbidden}
    end)

    reject(&Accounts.create_oidc_trust_policy/2)
    reject(&Accounts.delete_oidc_trust_policy/2)
    assert_raise UnauthorizedError, fn -> WorkloadIdentities.initialize(socket) end

    for {event, params} <- [
          {"create_oidc_trust_policy", %{"oidc_trust_policy" => context.params}},
          {"delete_oidc_trust_policy", %{"policy-id" => "1"}}
        ] do
      assert_raise UnauthorizedError, fn -> AuthenticationSettingsLive.handle_event(event, params, socket) end
    end
  end

  test "an administrator demoted with the page open cannot create an identity", context do
    lv = open(context)
    {:ok, _} = Accounts.update_user_role_in_organization(context.user, context.organization, :viewer)
    Process.flag(:trap_exit, true)
    assert catch_exit(submit(lv, context.params))
    assert [] = Accounts.list_oidc_trust_policies(context.account)
  end
end
