defmodule Atlas.Agents.IdentityTest do
  use Atlas.DataCase, async: true

  alias Atlas.Agents
  alias Atlas.Agents.Identity
  alias Atlas.Audit.Activity
  alias Atlas.Repo
  alias Atlas.Slack.AgentIdentities
  alias Atlas.Slack.Channel

  test "normalizes configured bindings, tool groups, and requester rules" do
    changeset =
      Identity.changeset(%Identity{}, %{
        key: "Leadership",
        display_name: "Atlas Leadership",
        bindings: %{slack: %{app: :company, channel_ids: [" C123 ", "C123", ""], match_all_channels: false}},
        tool_groups: ["FINANCE", "documents", ""],
        tool_groups_by_agent: %{
          "conversation" => ["FINANCE"],
          systems_investigator: ["OBSERVABILITY"]
        },
        requester_rules: %{"FINANCE" => "Executive"}
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :key) == "leadership"
    assert Ecto.Changeset.get_field(changeset, :bindings)["slack"]["app"] == "company"
    assert Ecto.Changeset.get_field(changeset, :tool_groups) == ["finance", "documents"]

    assert Ecto.Changeset.get_field(changeset, :tool_groups_by_agent) == %{
             "conversation" => ["finance"],
             "systems_investigator" => ["observability"]
           }

    assert Ecto.Changeset.get_field(changeset, :requester_rules) == %{"finance" => "executive"}
  end

  test "resolves exact channel identities before workspace defaults" do
    channel = %Channel{slack_app: :company, channel_id: "C_LEADERSHIP", channel_name: "leadership"}

    insert_identity!(%{
      key: "internal",
      display_name: "Atlas Internal",
      bindings: %{slack: %{app: :company, match_all_channels: true}},
      tool_groups: ["documents"]
    })

    exact =
      insert_identity!(%{
        key: "leadership",
        display_name: "Atlas Leadership",
        bindings: %{slack: %{app: :company, channel_ids: ["C_LEADERSHIP"]}},
        priority: 10,
        tool_groups: ["finance", "documents"],
        service_user_email: "leadership-agent@example.com",
        memory_scope: :channel,
        requester_rules: %{"finance" => "executive"}
      })

    assert AgentIdentities.resolve_for_channel(:company, channel).id == exact.id

    identity = AgentIdentities.for_channel(:company, channel)

    assert identity.key == "leadership"
    assert identity.display_name == "Atlas Leadership"
    assert identity.service_user_email == "leadership-agent@example.com"
    assert identity.memory_scope == :channel
    assert identity.requester_rules == %{"finance" => "executive"}
    assert Identity.tool_groups_for_agent(identity, :conversation) == ["finance", "documents"]
    assert Identity.tool_groups_for_agent(identity, :systems_investigator) == []
  end

  test "ignores disabled identities" do
    channel = %Channel{slack_app: :company, channel_id: "C_DISABLED", channel_name: "disabled"}

    insert_identity!(%{
      key: "disabled",
      display_name: "Atlas Disabled",
      bindings: %{slack: %{app: :company, channel_ids: ["C_DISABLED"]}},
      enabled: false
    })

    assert AgentIdentities.resolve_for_channel(:company, channel) == nil
  end

  test "creates identities through the Agents context and records an audit activity" do
    assert {:ok, identity} =
             Agents.create_identity(%{
               key: "leadership",
               display_name: "Atlas Leadership",
               bindings: %{slack: %{app: :company, channel_ids: ["C_LEADERSHIP"]}},
               tool_groups: ["finance"]
             })

    activity = Repo.get_by!(Activity, action: "agent_identity.created")

    assert activity.target_type == "agent_identity"
    assert activity.target_id == identity.id
    assert activity.target_label == "Atlas Leadership"
    assert activity.metadata["identity_key"] == "leadership"
    assert activity.metadata["bindings"]["slack"]["channel_ids"] == ["C_LEADERSHIP"]
    assert activity.metadata["tool_groups"] == ["finance"]
    assert activity.metadata["dashboard_path"] == "/admin/identities"
  end

  test "deletes identities through the Agents context and records an audit activity" do
    identity =
      insert_identity!(%{
        key: "temporary-leadership",
        display_name: "Temporary Leadership",
        bindings: %{slack: %{app: :company, channel_ids: ["C_TEMPORARY"]}},
        tool_groups: ["documents"]
      })

    assert {:ok, deleted_identity} = Agents.delete_identity(identity)

    assert deleted_identity.id == identity.id
    assert Repo.get(Identity, identity.id) == nil

    activity = Repo.get_by!(Activity, action: "agent_identity.deleted")

    assert activity.target_type == "agent_identity"
    assert activity.target_id == identity.id
    assert activity.target_label == "Temporary Leadership"
    assert activity.metadata["identity_key"] == "temporary-leadership"
    assert activity.metadata["bindings"]["slack"]["channel_ids"] == ["C_TEMPORARY"]
    assert activity.metadata["tool_groups"] == ["documents"]
    assert activity.metadata["dashboard_path"] == "/admin/identities"
  end

  defp insert_identity!(attrs) do
    defaults = %{
      key: "identity-#{System.unique_integer([:positive])}",
      display_name: "Atlas Identity",
      bindings: %{slack: %{app: :company, channel_ids: [], match_all_channels: false}},
      enabled: true
    }

    %Identity{}
    |> Identity.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
