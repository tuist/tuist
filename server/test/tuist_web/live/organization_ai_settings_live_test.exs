defmodule TuistWeb.OrganizationAISettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Accounts.OrganizationAI
  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: user)
    stub(FeatureFlags, :organization_luft_enabled?, fn actor -> actor.id == organization.account.id end)
    %{user: user, account: organization.account, organization: organization, conn: log_in_user(conn, user)}
  end

  test "admin manages connections, models and default separately without revealing keys", %{
    conn: conn,
    user: user,
    account: account
  } do
    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/ai/routing")
    assert html =~ "No providers yet"
    refute has_element?(lv, "#organization-ai-model-form")
    assert has_element?(lv, ~s(a[href="/#{account.name}/settings/ai/routing"]))

    lv |> element("#add-ai-connection") |> render_click()
    assert_push_event(lv, "open-modal", %{id: "organization-ai-connection-modal"})

    render_change(lv, "change-connection", %{
      "_target" => ["connection", "provider"],
      "connection" => %{"provider" => "custom"}
    })

    html =
      lv
      |> form("#organization-ai-connection-form",
        connection: %{name: "Shared inference", base_url: "https://api.fireworks.ai/inference/v1", api_key: "test-secret"}
      )
      |> render_submit()

    refute html =~ "test-secret"
    assert_push_event(lv, "close-modal", %{id: "organization-ai-connection-modal"})
    assert {:ok, %{connections: [connection], models: [], default_model_id: nil}} = OrganizationAI.settings(user, account)
    assert has_element?(lv, "#ai-connection-#{connection.id}", "Shared inference")
    assert has_element?(lv, "#organization-ai-model-form")

    for {name, id} <- [{"Fast", "accounts/fireworks/models/fast"}, {"Deep", "accounts/fireworks/models/deep"}] do
      lv |> element("#add-ai-model") |> render_click()

      lv
      |> form("#organization-ai-model-form", model: %{name: name, connection_id: connection.id, model_id: id})
      |> render_submit()
    end

    assert {:ok, %{models: [fast, deep], default_model_id: nil}} = OrganizationAI.settings(user, account)

    menu_html = lv |> render() |> Floki.parse_document!()

    for {event, id} <- [
          {"edit-connection", connection.id},
          {"remove-connection", connection.id},
          {"edit-model", fast.id},
          {"remove-model", fast.id}
        ] do
      assert menu_html |> Floki.find(~s([phx-click="#{event}"][phx-value-id="#{id}"])) |> Enum.any?()
    end

    lv |> form("#organization-ai-default-form", default: %{model_id: deep.id}) |> render_submit()
    assert {:ok, %{default_model_id: selected}} = OrganizationAI.settings(user, account)
    assert selected == deep.id

    lv |> form("#organization-ai-default-form", default: %{model_id: "none"}) |> render_submit()
    assert {:ok, %{default_model_id: nil}} = OrganizationAI.settings(user, account)
    lv |> form("#organization-ai-default-form", default: %{model_id: deep.id}) |> render_submit()

    render_click(lv, "edit-connection", %{"id" => to_string(connection.id)})

    render_change(lv, "change-connection", %{
      "_target" => ["connection", "provider"],
      "connection" => %{
        "_id" => to_string(connection.id),
        "provider" => "custom",
        "name" => connection.name,
        "base_url" => connection.base_url
      }
    })

    assert lv
           |> render()
           |> Floki.parse_document!()
           |> Floki.find(~s(input[name="connection[api_key]"][type="password"][value=""]))
           |> Enum.any?()

    lv
    |> form("#organization-ai-connection-form", connection: %{name: "Renamed connection", api_key: ""})
    |> render_submit()

    assert has_element?(lv, "#ai-model-#{fast.id}", "Renamed connection")
    assert {:ok, %{models: [_, _], default_model_id: ^selected}} = OrganizationAI.settings(user, account)

    render_click(lv, "edit-model", %{"id" => to_string(fast.id)})

    lv
    |> form("#organization-ai-model-form", model: %{name: "Faster", model_id: "accounts/fireworks/models/faster"})
    |> render_submit()

    assert has_element?(lv, "#ai-model-#{fast.id}", "Faster")
    render_click(lv, "remove-connection", %{"id" => to_string(connection.id)})
    assert render(lv) =~ "all models using this provider"
    assert_push_event(lv, "open-modal", %{id: "organization-ai-removal"})
    assert {:ok, %{connections: [_]}} = OrganizationAI.settings(user, account)
    render_click(lv, "confirm-removal")
    assert {:ok, %{connections: [], models: [], default_model_id: nil}} = OrganizationAI.settings(user, account)
  end

  test "admin adds, edits and removes task routes, with the default as fallback", %{
    conn: conn,
    user: user,
    account: account
  } do
    {:ok, lv, _} = live(conn, ~p"/#{account.name}/settings/ai/routing")
    assert has_element?(lv, "#add-ai-route[disabled]")
    assert has_element?(lv, "#ai-routes-table", "Add a model before adding a route.")

    {:ok, connection} =
      OrganizationAI.save_connection(user, account, %{
        "name" => "Atlas tuist-pulse",
        "base_url" => "https://api.together.ai/v1",
        "api_key" => "key"
      })

    {:ok, explainer} =
      OrganizationAI.save_model(user, account, %{
        "connection_id" => connection.id,
        "name" => "tuist-pulse",
        "model_id" => "tuist-pulse"
      })

    {:ok, classifier} =
      OrganizationAI.save_model(user, account, %{
        "connection_id" => connection.id,
        "name" => "Tev1 4B",
        "model_id" => "together/Tev1-4B-experimental"
      })

    {:ok, lv, _} = live(conn, ~p"/#{account.name}/settings/ai/routing")
    assert has_element?(lv, "#ai-routes-no-default", "tasks without a route don't send requests")
    refute has_element?(lv, "#add-ai-route[disabled]")

    lv |> element("#add-ai-route") |> render_click()
    assert_push_event(lv, "open-modal", %{id: "organization-ai-route-modal"})
    html = render_change(lv, "change-route", %{"_target" => ["route", "category"], "route" => %{"category" => "pulse"}})
    options = html |> Floki.parse_document!() |> Floki.find(~s([id^="ai-route-task-"] [data-part="item"]))
    assert Floki.text(options) =~ "Group related observations"
    assert Floki.text(options) =~ "Name and explain symptoms"

    lv
    |> form("#organization-ai-route-form", route: %{task: "pulse_grouping", model_id: classifier.id})
    |> render_submit()

    assert_push_event(lv, "close-modal", %{id: "organization-ai-route-modal"})
    assert {:ok, %{routes: [route]}} = OrganizationAI.settings(user, account)
    assert {route.task, route.model_id} == {:pulse_grouping, classifier.id}
    assert has_element?(lv, "#ai-route-#{route.id}", "Pulse")
    assert has_element?(lv, "#ai-route-#{route.id}", "Group related observations")
    assert has_element?(lv, "#ai-route-#{route.id}", "Tev1 4B")
    assert has_element?(lv, "#ai-route-#{route.id}", "Atlas tuist-pulse")

    # A routed task is no longer offered for a new route, and a stale duplicate is refused.
    lv |> element("#add-ai-route") |> render_click()

    task_values = fn ->
      lv |> render() |> Floki.parse_document!() |> Floki.attribute(~s([id^="ai-route-task-"] option), "value")
    end

    assert task_values.() == ["", "none", "pulse_explanation"]

    # A stale page can still submit a routed task; the modal stays open with an error.
    html =
      render_submit(lv, "save-route", %{
        "route" => %{"category" => "pulse", "task" => "pulse_grouping", "model_id" => to_string(explainer.id)}
      })

    assert html =~ "Each task can have only one route."
    assert task_values.() == ["", "none", "pulse_explanation"]
    assert {:ok, %{routes: [%{model_id: model_id}]}} = OrganizationAI.settings(user, account)
    assert model_id == classifier.id

    html =
      lv
      |> form("#organization-ai-route-form", route: %{task: "pulse_explanation", model_id: explainer.id})
      |> render_submit()

    refute html =~ "Each task can have only one route"
    refute has_element?(lv, "#ai-routes-no-default")
    assert has_element?(lv, "#add-ai-route[disabled]")

    render_click(lv, "edit-route", %{"id" => to_string(route.id)})
    assert_push_event(lv, "open-modal", %{id: "organization-ai-route-modal"})

    lv
    |> form("#organization-ai-route-form", route: %{model_id: explainer.id})
    |> render_submit()

    assert {:ok, %{routes: [%{task: :pulse_grouping, model_id: model_id}, _]}} = OrganizationAI.settings(user, account)
    assert model_id == explainer.id

    # Removing a model while no default is selected says its routed tasks stop sending requests.
    render_click(lv, "remove-model", %{"id" => to_string(explainer.id)})
    assert render(lv) =~ "if no default remains, they and other tasks without a route stop sending requests"
    render_click(lv, "cancel-removal")

    render_click(lv, "remove-route", %{"id" => to_string(route.id)})
    assert render(lv) =~ "Remove the route for Group related observations?"
    assert render(lv) =~ "this task stops sending requests until you add a route or select a default"
    render_click(lv, "confirm-removal")
    assert {:ok, %{routes: [%{task: :pulse_explanation}]}} = OrganizationAI.settings(user, account)
    assert has_element?(lv, "#ai-routes-no-default")

    lv |> form("#organization-ai-default-form", default: %{model_id: explainer.id}) |> render_submit()
    refute has_element?(lv, "#ai-routes-no-default")

    # Editing a route another session removed leaves the page, as editing a removed model does.
    [%{id: stale_id}] = elem(OrganizationAI.settings(user, account), 1).routes
    render_click(lv, "edit-route", %{"id" => to_string(stale_id)})
    assert {:ok, :ok} = OrganizationAI.remove_route(user, account, stale_id)

    render_submit(lv, "save-route", %{
      "route" => %{"_id" => to_string(stale_id), "task" => "pulse_explanation", "model_id" => to_string(classifier.id)}
    })

    assert_redirect(lv, ~p"/#{account.name}/settings")
  end

  test "members cannot access settings and flag-off accounts have no AI navigation or direct access", %{
    conn: conn,
    account: account,
    organization: org
  } do
    member = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(member, org)
    assert_raise NotFoundError, fn -> live(log_in_user(conn, member), ~p"/#{account.name}/settings/ai/routing") end
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> false end)
    {:ok, lv, _} = live(conn, ~p"/#{account.name}/settings")
    refute has_element?(lv, ~s(a[href="/#{account.name}/settings/ai/routing"]))
    assert_raise NotFoundError, fn -> live(conn, ~p"/#{account.name}/settings/ai/routing") end
  end

  test "flag revocation while settings are open prevents writes", %{conn: conn, user: user, account: account} do
    {:ok, lv, _} = live(conn, ~p"/#{account.name}/settings/ai/routing")
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> false end)

    lv
    |> form("#organization-ai-connection-form",
      connection: %{api_key: "test-secret"}
    )
    |> render_submit()

    assert_redirect(lv, ~p"/#{account.name}/settings")
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
    assert {:ok, %{connections: []}} = OrganizationAI.settings(user, account)
  end

  test "validation clears submitted provider secrets", %{conn: conn, account: account} do
    {:ok, lv, _} = live(conn, ~p"/#{account.name}/settings/ai/routing")

    render_change(lv, "change-connection", %{
      "_target" => ["connection", "provider"],
      "connection" => %{"provider" => "custom"}
    })

    html =
      lv
      |> form("#organization-ai-connection-form",
        connection: %{name: "", base_url: "https://api.openai.com/v1", api_key: "test-secret"}
      )
      |> render_submit()

    assert html =~ "a valid API key"
    refute html =~ "test-secret"
  end

  test "provider selection reveals custom fields and preserves saved endpoint configuration on edit", %{
    conn: conn,
    user: user,
    account: account
  } do
    {:ok, lv, _} = live(conn, ~p"/#{account.name}/settings/ai/routing")
    assert has_element?(lv, "#organization-ai-connection-form[phx-change='change-connection']")
    lv |> element("#add-ai-connection") |> render_click()

    for {selection, name, url} <- [
          {"fireworks", "Fireworks AI", "https://api.fireworks.ai/inference/v1"},
          {"together", "Together AI", "https://api.together.ai/v1"},
          {"openai", "OpenAI", "https://api.openai.com/v1"},
          {"custom", "", ""}
        ] do
      html =
        render_change(lv, "change-connection", %{
          "_target" => ["connection", "provider"],
          "connection" => %{"provider" => selection, "name" => "OpenAI", "api_key" => "never-retain"}
        })

      document = Floki.parse_document!(html)
      assert Floki.attribute(document, ~s(input[name="connection[name]"]), "value") == [name]
      assert Floki.attribute(document, ~s(input[name="connection[base_url]"]), "value") == [url]

      for field <- ["name", "base_url"] do
        types = Floki.attribute(document, ~s(input[name="connection[#{field}]"]), "type")
        assert types == ["hidden"] == (selection != "custom")
      end

      refute html =~ "never-retain"
    end

    lv
    |> form("#organization-ai-connection-form",
      connection: %{
        name: "Our inference",
        base_url: "https://1.1.1.1/custom/v2",
        api_key: "custom-key"
      }
    )
    |> render_submit()

    assert {:ok, %{connections: [%{base_url: "https://1.1.1.1/custom/v2"} = provider]}} =
             OrganizationAI.settings(user, account)

    refute Map.has_key?(provider, :provider)
    refute Map.has_key?(provider, :api_key)
    assert has_element?(lv, "#ai-connection-#{provider.id}", "https://1.1.1.1/custom/v2")

    html = render_click(lv, "edit-connection", %{"id" => to_string(provider.id)})
    document = Floki.parse_document!(html)
    assert Floki.attribute(document, ~s(input[name="connection[name]"]), "value") == ["Our inference"]

    assert Floki.find(document, ~s(input[name="connection[base_url]"][type="hidden"])) == []

    lv
    |> form("#organization-ai-connection-form", connection: %{name: "Renamed inference", api_key: ""})
    |> render_submit()

    assert {:ok, %{connections: [%{name: "Renamed inference", base_url: "https://1.1.1.1/custom/v2"}]}} =
             OrganizationAI.settings(user, account)

    render_click(lv, "add-connection")
    lv |> form("#organization-ai-connection-form", connection: %{api_key: "preset-key"}) |> render_submit()
    assert {:ok, %{connections: connections}} = OrganizationAI.settings(user, account)
    preset = Enum.find(connections, &(&1.base_url == "https://api.openai.com/v1"))
    assert preset.name == "OpenAI"

    html = render_click(lv, "edit-connection", %{"id" => to_string(preset.id)})
    document = Floki.parse_document!(html)

    assert Floki.attribute(document, ~s(input[name="connection[base_url]"][type="hidden"]), "value") == [
             "https://api.openai.com/v1"
           ]

    lv |> form("#organization-ai-connection-form", connection: %{api_key: ""}) |> render_submit()
    assert {:ok, %{connections: saved}} = OrganizationAI.settings(user, account)
    assert Enum.find(saved, &(&1.id == preset.id)) == preset
  end

  test "Add provider offers Claude linking and API keys when linked billing is configured", %{
    conn: conn,
    account: account
  } do
    stub(Tuist.Environment, :anthropic_linked_billing_config, fn ->
      Map.new(
        ~w(client_id client_assertion_audience organization_id workspace_id service_account_id federation_rule_id)a,
        &{&1, "configured"}
      )
    end)

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/ai/routing")
    document = Floki.parse_document!(html)

    assert has_element?(lv, "#add-ai-provider-dropdown")
    refute has_element?(lv, "button#add-ai-connection")

    assert Floki.attribute(document, "a#link-claude-organization", "href") == [
             "/integrations/claude/start?account_id=#{account.id}"
           ]

    assert Floki.attribute(document, "#add-ai-connection", "phx-click") == ["add-connection"]
    render_click(lv, "add-connection")
    assert_push_event(lv, "open-modal", %{id: "organization-ai-connection-modal"})
  end
end
