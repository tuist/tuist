defmodule Atlas.Slack.AgentIdentitiesConfigTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Agents.Identity
  alias Atlas.Slack.AgentConfig
  alias Atlas.Slack.AgentIdentities
  alias Atlas.Slack.Channel

  setup :verify_on_exit!

  test "returns the default identity when no configured identity matches" do
    configured_identities = [
      %{
        "workspace" => "company",
        "channel_id" => "C_POLICY",
        "persona" => "leadership",
        "tool_groups" => ["finance"]
      }
    ]

    channel = %Channel{slack_app: :company, channel_id: "C_OTHER", channel_name: "other-fixture"}

    assert %Identity{key: "default", persona: :default, tool_groups: []} =
             AgentIdentities.for_channel(:company, channel, configured_identities)
  end

  test "matches configured identities by workspace and channel id" do
    configured_identities = [
      %{
        "workspace" => "company",
        "channel_id" => "C_POLICY",
        "persona" => "leadership",
        "tool_groups" => ["finance", "documents"]
      }
    ]

    company_channel = %Channel{
      slack_app: :company,
      channel_id: "C_POLICY",
      channel_name: "fixture-channel"
    }

    community_channel = %Channel{
      slack_app: :community,
      channel_id: "C_POLICY",
      channel_name: "fixture-channel"
    }

    assert %Identity{persona: :leadership, tool_groups: ["finance", "documents"]} =
             identity = AgentIdentities.for_channel(:company, company_channel, configured_identities)

    assert Identity.tool_groups_for_agent(identity, :conversation) == ["finance", "documents"]
    assert Identity.tool_groups_for_agent(identity, :systems_investigator) == []

    assert %Identity{key: "default", persona: :default, tool_groups: []} =
             AgentIdentities.for_channel(:community, community_channel, configured_identities)
  end

  test "normalizes atom and string configured identity values" do
    configured_identities = [
      [
        slack_app: :company,
        channel_id: "C_NORMALIZE",
        persona: :leadership,
        tool_groups: [:finance, "FINANCE", " "]
      ]
    ]

    channel = %Channel{slack_app: :company, channel_id: "C_NORMALIZE", channel_name: "normalize-fixture"}

    assert %Identity{persona: :leadership, tool_groups: ["finance"]} =
             AgentIdentities.for_channel("company", channel, configured_identities)
  end

  test "leaves omitted display name and service user unset" do
    configured_identities = [
      %{
        "workspace" => "company",
        "channel_id" => "C_POLICY",
        "mcp_tool_groups" => ["documents", "finance"]
      }
    ]

    channel = %Channel{slack_app: :company, channel_id: "C_POLICY", channel_name: "policy-fixture"}

    identity = AgentIdentities.for_channel(:company, channel, configured_identities)

    assert identity.display_name == "Atlas"
    assert identity.service_user_email == nil
    assert identity.tool_groups == ["documents", "finance"]
  end

  test "supports explicit tool group mappings per agent" do
    configured_identities = [
      %{
        "workspace" => "company",
        "channel_id" => "C_POLICY",
        "tool_groups" => ["finance", "observability"],
        "tool_groups_by_agent" => %{
          "conversation" => ["finance"],
          "systems_investigator" => ["observability"]
        }
      }
    ]

    channel = %Channel{slack_app: :company, channel_id: "C_POLICY", channel_name: "fixture-channel"}

    identity = AgentIdentities.for_channel(:company, channel, configured_identities)

    assert identity.tool_groups == ["finance", "observability"]
    assert Identity.tool_groups_for_agent(identity, :conversation) == ["finance"]
    assert Identity.tool_groups_for_agent(identity, :systems_investigator) == ["observability"]
  end

  test "includes per-agent groups in the aggregate identity groups" do
    configured_identities = [
      %{
        "workspace" => "company",
        "channel_id" => "C_POLICY",
        "tool_groups_by_agent" => %{
          "conversation" => ["finance"]
        }
      }
    ]

    channel = %Channel{slack_app: :company, channel_id: "C_POLICY", channel_name: "fixture-channel"}

    identity = AgentIdentities.for_channel(:company, channel, configured_identities)

    assert identity.tool_groups == ["finance"]
    assert Identity.tool_groups_for_agent(identity, :conversation) == ["finance"]
    assert Identity.tool_groups_for_agent(identity, :systems_investigator) == []
  end

  test "does not match channel-name-only configured identities" do
    configured_identities = [
      [
        slack_app: :company,
        channel_name: "fixture-channel",
        persona: :leadership,
        tool_groups: [:finance]
      ]
    ]

    channel = %Channel{slack_app: :company, channel_id: "C_POLICY", channel_name: "fixture-channel"}

    assert %Identity{key: "default", persona: :default, tool_groups: []} =
             AgentIdentities.for_channel(:company, channel, configured_identities)
  end

  test "preserves explicit falsy configured identity values" do
    configured_identities = [
      %{
        "match_all_channels" => true,
        slack_app: :company,
        channel_id: "C_EXACT",
        match_all_channels: false,
        persona: :leadership
      }
    ]

    exact_channel = %Channel{slack_app: :company, channel_id: "C_EXACT", channel_name: "exact-fixture"}
    other_channel = %Channel{slack_app: :company, channel_id: "C_OTHER", channel_name: "other-fixture"}

    assert %Identity{persona: :leadership} =
             AgentIdentities.for_channel(:company, exact_channel, configured_identities)

    assert %Identity{key: "default", persona: :default} =
             AgentIdentities.for_channel(:company, other_channel, configured_identities)
  end

  test "uses configured leadership identity from runtime config" do
    stub(AgentConfig, :identities, fn ->
      [
        %{
          "workspace" => "company",
          "channel_id" => "C_LEADERSHIP",
          "key" => "leadership",
          "display_name" => "Leadership",
          "persona" => "leadership",
          "memory_scope" => "channel",
          "requester_rules" => %{"finance" => "executive"},
          "tool_groups_by_agent" => %{
            "conversation" => ["finance", "documents"],
            "systems_investigator" => []
          }
        }
      ]
    end)

    channel = %Channel{slack_app: :company, channel_id: "C_LEADERSHIP", channel_name: "leadership"}

    assert %Identity{key: "leadership", persona: :leadership, tool_groups: ["finance", "documents"]} =
             identity = AgentIdentities.for_channel(:company, channel)

    assert identity.memory_scope == :channel
    assert identity.requester_rules == %{"finance" => "executive"}
    assert Identity.tool_groups_for_agent(identity, :conversation) == ["finance", "documents"]
    assert Identity.tool_groups_for_agent(identity, :systems_investigator) == []
  end

  test "does not use a leadership identity without persisted or configured identities" do
    channel = %Channel{slack_app: :company, channel_id: "C_LEADERSHIP", channel_name: "leadership"}

    assert %Identity{key: "default", persona: :default, tool_groups: []} =
             AgentIdentities.for_channel(:company, channel, [])
  end

  test "returns persona instructions only for persona-specific identities" do
    assert Identity.persona_instructions(Identity.default()) == nil

    assert Identity.persona_instructions(%Identity{persona: :leadership}) =~
             "Act as a leadership operator"
  end
end
