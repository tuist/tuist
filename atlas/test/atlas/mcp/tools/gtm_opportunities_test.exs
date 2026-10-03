defmodule Atlas.MCP.Tools.GTMOpportunitiesTest do
  use Atlas.MCP.ToolCase, async: true
  use Mimic

  alias Atlas.GTM
  alias Atlas.MCP.Tools.ConvertGTMOpportunity
  alias Atlas.MCP.Tools.GetGTMOpportunity
  alias Atlas.MCP.Tools.ListGTMAdvocates
  alias Atlas.MCP.Tools.ListGTMOpportunities
  alias Atlas.MCP.Tools.ListGTMResearchTopics
  alias Atlas.MCP.Tools.NotifyGTMOpportunity
  alias Atlas.MCP.Tools.PrepareGTMOpportunityOutreach
  alias Atlas.MCP.Tools.ReviewGTMOpportunity
  alias Atlas.Slack.API

  setup :verify_on_exit!

  defp insert_opportunity! do
    {:ok, signal} =
      GTM.record_gtm_signal(%{
        company_name: "Acme Platforms",
        company_key: "domain:acme.example",
        domain: "acme.example",
        source: "brave",
        source_ref: "https://acme.example/blog/ios-ci",
        source_url: "https://acme.example/blog/ios-ci",
        title: "How Acme scales iOS CI with Swift modules",
        excerpt: "Xcode build times and developer productivity work for a large mobile CI setup.",
        matched_terms: ["iOS", "Swift", "Xcode", "monorepo", "developer productivity"],
        signal_kind: "engineering_blog",
        confidence: 82,
        observed_at: ~U[2026-06-01 12:00:00Z],
        metadata: %{}
      })

    GTM.get_gtm_opportunity(signal.opportunity_id)
  end

  defp insert_advocate_opportunity! do
    {:ok, signal} =
      GTM.record_gtm_signal(%{
        company_name: "Acme Mobile",
        company_key: "github-company:acme-mobile",
        domain: nil,
        source: "github",
        source_ref: "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
        source_url: "https://github.com/mobiledev/ios-app/blob/main/Project.swift",
        title: "mobiledev/ios-app: Project.swift",
        excerpt: "Tuist Project.swift for a Swift iOS app.",
        matched_terms: ["Tuist", "Project.swift", "Swift", "iOS"],
        signal_kind: "tuist_mention",
        confidence: 95,
        observed_at: ~U[2026-06-01 12:00:00Z],
        metadata: %{
          "mention_type" => "tuist_public_mention",
          "person" => %{
            "login" => "mobiledev",
            "name" => "Maya Singh",
            "company" => "Acme Mobile",
            "github_url" => "https://github.com/mobiledev",
            "title" => "Public Tuist advocate",
            "confidence" => 86
          }
        }
      })

    GTM.get_gtm_opportunity(signal.opportunity_id)
  end

  test "lists GTM opportunities" do
    _opportunity = insert_opportunity!()

    assert {:ok, %{gtm_opportunities: [opportunity], count: 1}} =
             execute_tool(ListGTMOpportunities, conn_for(nil), %{"status" => "new"})

    assert opportunity.company_name == "Acme Platforms"
    assert opportunity.score > 0
  end

  test "lists GTM research topics" do
    assert {:ok, %{gtm_research_topics: topics, count: count}} =
             execute_tool(ListGTMResearchTopics, conn_for(nil), %{})

    assert count == length(topics)
    assert Enum.any?(topics, &(&1.topic == "iOS at scale" and &1.topic_source == "curated"))
  end

  test "lists public Tuist advocates" do
    _opportunity = insert_advocate_opportunity!()

    assert {:ok, %{gtm_advocates: [advocate], count: 1}} =
             execute_tool(ListGTMAdvocates, conn_for(nil), %{})

    assert advocate.full_name == "Maya Singh"
    assert advocate.profile_url == "https://github.com/mobiledev"
    assert advocate.opportunity.company_name == "Acme Mobile"
    assert advocate.evidence_signal.signal_kind == "tuist_mention"
  end

  test "gets a GTM opportunity with details" do
    opportunity = insert_opportunity!()

    assert {:ok, %{gtm_opportunity: payload}} =
             execute_tool(GetGTMOpportunity, conn_for(nil), %{"opportunity_id" => opportunity.id})

    assert payload.id == opportunity.id
    assert [%{title: "How Acme scales iOS CI with Swift modules"}] = payload.signals
  end

  test "reviews a GTM opportunity" do
    opportunity = insert_opportunity!()

    assert {:ok, %{gtm_opportunity: payload}} =
             execute_tool(ReviewGTMOpportunity, conn_for(nil), %{
               "opportunity_id" => opportunity.id,
               "status" => "qualified"
             })

    assert payload.status == "qualified"
  end

  test "notifies a GTM opportunity in Slack" do
    opportunity = insert_opportunity!()

    expect(API, :post_message, fn :company, "C0AGV3YU8ET", text, blocks ->
      assert text =~ "Acme Platforms"
      assert is_list(blocks)
      {:ok, %{"ok" => true, "channel" => "C0AGV3YU8ET", "ts" => "1717400000.000100"}}
    end)

    assert {:ok, %{gtm_opportunity: payload}} =
             execute_tool(NotifyGTMOpportunity, conn_for(nil), %{
               "opportunity_id" => opportunity.id,
               "force" => true
             })

    assert payload.slack_notification_channel_id == "C0AGV3YU8ET"
    assert payload.slack_notification_thread_ts == "1717400000.000100"
  end

  test "prepares a GTM opportunity for outreach" do
    opportunity = insert_opportunity!()

    expect(API, :post_message, fn :company, "C0AGV3YU8ET", text, blocks ->
      assert text =~ "Acme Platforms"
      assert is_list(blocks)
      {:ok, %{"ok" => true, "channel" => "C0AGV3YU8ET", "ts" => "1717400000.000100"}}
    end)

    assert {:ok, %{gtm_opportunity: payload, contacts: [], contact_error: "Apollo is not configured."}} =
             execute_tool(PrepareGTMOpportunityOutreach, conn_for(nil), %{
               "opportunity_id" => opportunity.id,
               "force" => true
             })

    assert payload.slack_notification_thread_ts == "1717400000.000100"
  end

  test "converts a GTM opportunity into an account" do
    opportunity = insert_opportunity!()

    assert {:ok, %{account: account, gtm_opportunity: payload}} =
             execute_tool(ConvertGTMOpportunity, conn_for(nil), %{"opportunity_id" => opportunity.id})

    assert account.name == "Acme Platforms"
    assert account.primary_domain == "acme.example"
    assert payload.status == "converted"
  end
end
