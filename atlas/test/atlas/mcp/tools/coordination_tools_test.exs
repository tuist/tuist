defmodule Atlas.MCP.Tools.CoordinationToolsTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Audit.Activity
  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Subscription
  alias Atlas.Integrations
  alias Atlas.MCP.Tools.ActOnBriefItem
  alias Atlas.MCP.Tools.GetBrief
  alias Atlas.MCP.Tools.ListBriefs
  alias Atlas.MCP.Tools.ListProductTraces
  alias Atlas.Product

  test "lists, reads, and acts on leadership briefs for executives" do
    {brief, item} = insert_brief!()
    conn = executive_mcp_conn()

    assert {:ok, %{briefs: [listed], count: 1}} = execute_tool(ListBriefs, conn, %{})
    assert listed.id == brief.id
    assert listed.domains == ["accounts", "product"]
    assert Map.has_key?(listed, :slack_channel_id)
    assert Map.has_key?(listed, :slack_thread_ts)
    refute Map.has_key?(listed, :url)

    assert {:ok, fetched} = execute_tool(GetBrief, conn, %{"brief_id" => brief.id})
    assert [%{id: item_id, domain: "accounts"}] = fetched.items
    assert item_id == item.id

    assert {:ok, acted_on} =
             execute_tool(ActOnBriefItem, conn, %{
               "brief_item_id" => item.id,
               "action" => "complete",
               "note" => "The renewal conversation is booked."
             })

    assert acted_on.status == "completed"
    assert acted_on.resolution_note == "The renewal conversation is booked."

    assert Repo.exists?(
             from activity in Activity,
               where:
                 activity.target_id == ^item.id and activity.action == "brief_item.completed" and
                   activity.interface == "mcp"
           )
  end

  test "rejects leadership brief access for employees" do
    employee = %{role: :employee} |> insert_user!() |> mcp_conn()

    assert {:error, "Leadership brief tools are only available to executives."} =
             execute_tool(ListBriefs, employee, %{})
  end

  test "lists observed product traces" do
    trace = insert_product_trace!()

    assert {:ok, %{traces: [serialized], count: 1}} =
             execute_tool(ListProductTraces, nil, %{"kind" => "pull_request_merged"})

    assert serialized.id == trace.id
    assert serialized.repository == "tuist/atlas"
    assert serialized.labels == ["release"]
  end

  defp insert_brief! do
    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        label: "Leadership weekly",
        audience_key: "leadership-#{System.unique_integer([:positive])}",
        cadence: "weekly",
        domains: ["accounts", "product"],
        slack_app: "company",
        slack_channel_id: "C-LEADERSHIP",
        max_sensitivity: "restricted",
        attention_budget: 8,
        enabled: true
      })
      |> Repo.insert!()

    brief =
      %Brief{brief_subscription_id: subscription.id}
      |> Brief.changeset(%{
        cadence: "weekly",
        period_start: ~U[2026-07-13 00:00:00Z],
        period_end: ~U[2026-07-20 00:00:00Z],
        status: "material",
        headline: "Weekly leadership brief",
        summary: "Accounts: one renewal needs attention.",
        attention_budget: 8,
        sensitivity: "internal",
        generation_mode: "deterministic"
      })
      |> Repo.insert!()

    item =
      %BriefItem{brief_id: brief.id}
      |> BriefItem.changeset(%{
        domain: "accounts",
        kind: "follow_up",
        title: "Book the renewal conversation",
        detail: "The renewal has no scheduled conversation.",
        severity: "warning",
        sensitivity: "internal",
        materiality_score: Decimal.new("0.82"),
        suggested_action: "Book the renewal conversation.",
        completion_condition: "The conversation is scheduled.",
        fingerprint: "accounts:renewal:book-call",
        position: 0,
        status: "open"
      })
      |> Repo.insert!()

    {brief, item}
  end

  defp insert_product_trace! do
    {:ok, app} =
      Integrations.create_github_app(%{
        name: "Product tool app",
        webhook_secret: "secret",
        app_id: "#{System.unique_integer([:positive])}",
        private_key: "private-key",
        installation_id: "#{System.unique_integer([:positive])}"
      })

    {:ok, repository} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "atlas"})

    {:ok, trace} =
      Product.record_trace(%{
        provider: "github",
        kind: "pull_request_merged",
        external_id: "pull_request:42:merged",
        github_repository_id: repository.id,
        repository_full_name: "tuist/atlas",
        number: 42,
        title: "Ship the coordination system",
        url: "https://github.com/tuist/atlas/pull/42",
        author_login: "octocat",
        occurred_at: ~U[2026-07-20 10:00:00Z],
        labels: ["release"],
        sensitivity: "internal"
      })

    trace
  end
end
