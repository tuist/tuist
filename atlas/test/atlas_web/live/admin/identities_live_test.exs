defmodule AtlasWeb.Admin.IdentitiesLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Atlas.Agents.Identity
  alias Atlas.Audit.Activity
  alias Atlas.Repo
  alias Atlas.Slack
  alias Atlas.Slack.AgentConfig
  alias Atlas.Slack.AgentIdentities
  alias Atlas.Slack.Channel

  setup :verify_on_exit!

  test "renders the identities panel for executives", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{email: "identities-executive@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/admin/identities")

    assert has_element?(view, "#admin-identities")
    assert has_element?(view, ~s(a#admin-slack-connect[href="/slack/install"]), "Connect Slack")
    assert has_element?(view, "#admin-identity-create-trigger")
    refute has_element?(view, "#admin-identities-count")
    assert has_element?(view, "#admin-persisted-identities-empty-state")
    assert has_element?(view, "#admin-configured-identities-empty-state")
    assert has_element?(view, ~s(a[href="/admin/identities"]), "Identities")
    refute render(view) =~ "Leadership identities"
  end

  test "renders persisted identities regardless of persona", %{conn: conn} do
    %Identity{}
    |> Identity.changeset(%{
      key: "default-slack",
      display_name: "Default Slack",
      enabled: true,
      priority: 0,
      bindings: %{
        slack: %{
          app: "company",
          channel_ids: ["C_GENERAL"],
          match_all_channels: false
        }
      },
      persona: :default,
      tool_groups: [],
      tool_groups_by_agent: %{
        conversation: [],
        systems_investigator: []
      },
      memory_scope: :global,
      requester_rules: %{},
      metadata: %{}
    })
    |> Repo.insert!()

    {conn, _executive} = log_in_user(conn, %{email: "default-identity-executive@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/admin/identities")

    assert has_element?(view, "#admin-identities-table", "Default Slack")
    assert has_element?(view, "#admin-identities-table", "Global memory")
  end

  test "handles workspace and channel dropdown events", %{conn: conn} do
    {:ok, _zeta_channel} =
      Slack.add_channel(%{
        slack_app: :company,
        channel_id: "C_COMPANY_ZETA",
        channel_name: "zeta"
      })

    {:ok, _company_channel} =
      Slack.add_channel(%{
        slack_app: :company,
        channel_id: "C_COMPANY_LEADERSHIP",
        channel_name: "leadership"
      })

    {:ok, _alpha_channel} =
      Slack.add_channel(%{
        slack_app: :company,
        channel_id: "C_COMPANY_ALPHA",
        channel_name: "alpha"
      })

    {conn, _executive} = log_in_user(conn, %{email: "identity-channels-executive@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/admin/identities")

    assert channel_dropdown_labels(view) == [
             "Every channel",
             "#alpha",
             "#leadership",
             "#zeta"
           ]

    render_hook(view, "toggle_identity_channel", %{"value" => "C_COMPANY_LEADERSHIP"})
    assert_push_event(view, "open-dropdown", %{id: "admin-identity-channel-dropdown"})
    assert channel_checked?(view, "C_COMPANY_LEADERSHIP")

    render_hook(view, "toggle_identity_channel", %{"value" => "_all"})
    assert_push_event(view, "open-dropdown", %{id: "admin-identity-channel-dropdown"})
    assert channel_checked?(view, "_all")

    assert has_element?(view, "#admin-identities")
  end

  test "creates a Slack-bound identity", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{email: "identity-create-executive@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/admin/identities")

    render_submit(view, "create_identity", %{
      "identity" => %{
        "display_name" => "Leadership Browser",
        "slack_app" => "company",
        "channel_ids" => ["", "C_LEADERSHIP"],
        "memory_scope" => "channel",
        "tool_groups" => ["finance", "documents", "observability"]
      }
    })

    identity = Repo.get_by!(Identity, key: "leadership-browser")

    assert identity.display_name == "Leadership Browser"
    assert identity.persona == :leadership
    assert identity.memory_scope == :channel
    assert identity.requester_rules == %{"finance" => "executive"}
    assert identity.service_user_email == nil
    assert identity.tool_groups == ["finance", "documents", "observability"]
    assert Identity.tool_groups_for_agent(identity, :conversation) == ["finance", "documents"]
    assert Identity.tool_groups_for_agent(identity, :systems_investigator) == ["observability"]
    assert AgentIdentities.slack_binding(identity)["channel_ids"] == ["C_LEADERSHIP"]

    assert AgentIdentities.matches_channel?(identity, %Channel{
             slack_app: :company,
             channel_id: "C_LEADERSHIP",
             channel_name: "leadership"
           })

    refute AgentIdentities.matches_channel?(identity, %Channel{
             slack_app: :company,
             channel_id: "C_OTHER",
             channel_name: "other"
           })

    assert Repo.get_by!(Activity, action: "agent_identity.created").target_id == identity.id
    assert has_element?(view, "#identities-#{identity.id}", "Leadership Browser")
  end

  test "creates an identity available in every Slack channel when channels are blank", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{email: "identity-all-channels-executive@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/admin/identities")

    render_submit(view, "create_identity", %{
      "identity" => %{
        "display_name" => "Leadership",
        "slack_app" => "company",
        "channel_ids" => [""],
        "memory_scope" => "channel",
        "tool_groups" => ["finance", "documents"]
      }
    })

    identity = Repo.get_by!(Identity, key: "leadership")
    slack_binding = AgentIdentities.slack_binding(identity)

    assert slack_binding["channel_ids"] == []

    assert AgentIdentities.matches_channel?(identity, %Channel{
             slack_app: :company,
             channel_id: "C_ANY",
             channel_name: "any"
           })

    assert has_element?(view, "#identities-#{identity.id}", "company Slack, all channels")
  end

  test "deletes a persisted identity from the identities panel", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{email: "identity-delete-executive@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/admin/identities")

    render_submit(view, "create_identity", %{
      "identity" => %{
        "display_name" => "Temporary Leadership",
        "slack_app" => "company",
        "channel_ids" => ["C_LEADERSHIP"],
        "memory_scope" => "channel",
        "tool_groups" => ["finance", "documents"]
      }
    })

    identity = Repo.get_by!(Identity, key: "temporary-leadership")

    assert has_element?(view, "#identities-#{identity.id}", "Temporary Leadership")
    assert has_element?(view, "#delete-identity-#{identity.id}")

    view
    |> element("#delete-identity-#{identity.id}")
    |> render_click()

    assert Repo.get(Identity, identity.id) == nil
    assert Repo.get_by!(Activity, action: "agent_identity.deleted").target_id == identity.id
    refute has_element?(view, "#identities-#{identity.id}")
    assert has_element?(view, "#admin-persisted-identities-empty-state")
  end

  test "renders validation errors when identity creation fails", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{email: "identity-validation-executive@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/admin/identities")

    html =
      render_submit(view, "create_identity", %{
        "identity" => %{
          "display_name" => "",
          "slack_app" => "company",
          "channel_ids" => ["", "C_LEADERSHIP"],
          "memory_scope" => "channel",
          "tool_groups" => ["finance", "documents"]
        }
      })

    assert html =~ "can&#39;t be blank"
    assert Repo.aggregate(Identity, :count) == 0
  end

  test "renders configured identities separately from persisted identities", %{conn: conn} do
    stub(AgentConfig, :identities, fn ->
      [
        %{
          "workspace" => "company",
          "channel_id" => "C_GENERAL",
          "key" => "default-slack",
          "display_name" => "Default Slack",
          "persona" => "default",
          "memory_scope" => "global",
          "tool_groups_by_agent" => %{"conversation" => ["documents"]}
        },
        %{
          "workspace" => "company",
          "channel_id" => "C_LEADERSHIP",
          "key" => "leadership",
          "display_name" => "Leadership",
          "persona" => "leadership",
          "memory_scope" => "channel",
          "requester_rules" => %{"finance" => "executive"},
          "tool_groups_by_agent" => %{"conversation" => ["finance", "documents"]}
        }
      ]
    end)

    {conn, _executive} =
      log_in_user(conn, %{email: "configured-identities-executive@example.com", role: :executive})

    {:ok, view, _html} = live(conn, ~p"/admin/identities")

    assert has_element?(view, "#admin-configured-identities-list", "Leadership")
    assert has_element?(view, "#admin-configured-identities-list", "Default Slack")
    assert has_element?(view, "#configured-identity-source-0", "Configured")
  end

  test "redirects employees away from the identities panel", %{conn: conn} do
    {conn, _employee} = log_in_user(conn, %{email: "identities-employee@example.com", role: :employee})

    assert {:error, {:redirect, %{to: "/commercial/sales"}}} = live(conn, ~p"/admin/identities")
  end

  defp channel_dropdown_labels(view) do
    tree =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.to_tree()

    tree
    |> find_tree_by_id("admin-identity-channel-dropdown-content-portal")
    |> dropdown_item_labels()
  end

  defp channel_checked?(view, value) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> find_tree_by_id("admin-identity-channel-dropdown-content-portal")
    |> find_dropdown_item_by_value(value)
    |> checked_dropdown_item?()
  end

  defp find_tree_by_id(nodes, id) do
    Enum.find_value(nodes, fn
      {_, attrs, children} = node ->
        if {"id", id} in attrs do
          [node]
        else
          case find_tree_by_id(children, id) do
            [] -> nil
            found -> found
          end
        end

      _node ->
        nil
    end) || []
  end

  defp find_dropdown_item_by_value(nodes, value) do
    Enum.find_value(nodes, fn
      {_, attrs, children} = node ->
        if {"data-part", "item"} in attrs and {"data-value", value} in attrs do
          node
        else
          find_dropdown_item_by_value(children, value)
        end

      _node ->
        nil
    end)
  end

  defp checked_dropdown_item?(nil), do: false

  defp checked_dropdown_item?({_tag, _attrs, children}) do
    checked_checkbox_control?(children)
  end

  defp checked_checkbox_control?(nodes) do
    Enum.any?(nodes, fn
      {_, attrs, children} ->
        ({"class", "noora-checkbox-control"} in attrs and {"data-state", "checked"} in attrs) or
          checked_checkbox_control?(children)

      _node ->
        false
    end)
  end

  defp dropdown_item_labels(nodes) do
    Enum.flat_map(nodes, fn
      {_, attrs, children} ->
        labels =
          if {"data-part", "item"} in attrs do
            [dropdown_item_text(children)]
          else
            []
          end

        labels ++ dropdown_item_labels(children)

      _node ->
        []
    end)
  end

  defp dropdown_item_text(nodes) do
    nodes
    |> Enum.map_join("", fn
      text when is_binary(text) -> text
      {_, _, children} -> dropdown_item_text(children)
      _node -> ""
    end)
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end
end
