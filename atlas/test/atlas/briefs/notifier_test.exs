defmodule Atlas.Briefs.NotifierTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Notifier
  alias Atlas.Briefs.Subscription
  alias Atlas.Slack.API
  alias Atlas.Slack.Channel

  # `slack_channels.channel_id` is unique across the table, so the channel this
  # module syncs has to be its own. Tests inside a module run one at a time, so a
  # module-wide id cannot contend with itself the way a suite-wide one does.
  @slack_channel_id "C-NOTIFIER"

  setup :verify_on_exit!

  test "reconciles an ambiguous initial delivery before posting again" do
    brief = insert_brief!(status: "failed", failure_reason: ":timeout")

    expect(API, :find_message_by_metadata, fn :company, @slack_channel_id, "atlas_brief", brief_id ->
      assert brief_id == brief.id
      {:ok, %{"ts" => "1717400000.000100"}}
    end)

    reject(&API.post_message/5)

    assert {:ok, posted} = Notifier.notify(brief)
    assert posted.status == "posted"
    assert posted.slack_thread_ts == "1717400000.000100"
    assert is_nil(posted.failure_reason)
  end

  test "posts the brief when the channel history cannot be read" do
    brief = insert_brief!()

    expect(API, :find_message_by_metadata, fn :company, @slack_channel_id, "atlas_brief", _brief_id ->
      {:error, "not_in_channel"}
    end)

    expect(API, :post_message, fn :company, @slack_channel_id, _text, _blocks, opts ->
      assert opts[:client_msg_id] == brief.id
      {:ok, %{"ts" => "1717400000.000200"}}
    end)

    assert {:ok, posted} = Notifier.notify(brief)
    assert posted.status == "posted"
    assert posted.slack_thread_ts == "1717400000.000200"
  end

  test "a failed refresh keeps an already delivered brief posted" do
    brief = insert_brief!(status: "posted", slack_thread_ts: "1717400000.000100")

    expect(API, :update_message, fn :company, @slack_channel_id, "1717400000.000100", _text, _blocks, opts ->
      assert opts[:metadata].event_payload.key == brief.id
      {:error, :slack_down}
    end)

    assert {:error, :slack_down} = Notifier.notify(brief)
    stored = Repo.get!(Brief, brief.id)
    assert stored.status == "posted"
    assert stored.failure_reason == ":slack_down"
  end

  test "renders each domain in one Slack section even when item positions interleave" do
    brief = insert_brief!()
    insert_item!(brief, "accounts", "account:first", 0)
    insert_item!(brief, "finance", "finance:first", 1)
    insert_item!(brief, "accounts", "account:second", 2)
    brief = Repo.preload(brief, [:subscription, items: [:owner]], force: true)

    headings =
      brief
      |> Notifier.build_blocks()
      |> Enum.filter(&(get_in(&1, ["text", "text"]) in ["*Accounts*", "*Finance*"]))
      |> Enum.map(&get_in(&1, ["text", "text"]))

    assert headings == ["*Accounts*", "*Finance*"]
  end

  test "keeps the suggested move, completion condition, and source in Slack" do
    brief = insert_brief!()

    insert_item!(brief, "product", "product:release", 1, %{
      suggested_action: "Confirm the release communication owner.",
      completion_condition: "The release note is published.",
      source_path: "https://github.com/tuist/atlas/pull/42"
    })

    insert_item!(brief, "finance", "finance:vendors", 2, %{
      source_path: "/finance/vendors"
    })

    blocks =
      brief
      |> Repo.preload([:subscription, items: [:owner]], force: true)
      |> Notifier.build_blocks()

    item_text =
      blocks
      |> Enum.map(&get_in(&1, ["text", "text"]))
      |> Enum.find(&(is_binary(&1) and String.contains?(&1, "Review product")))

    assert item_text =~ "*Suggested next move:* Confirm the release communication owner."
    assert item_text =~ "*Done when:* The release note is published."
    assert item_text =~ "<https://github.com/tuist/atlas/pull/42|Open source>"

    finance_text =
      blocks
      |> Enum.map(&get_in(&1, ["text", "text"]))
      |> Enum.find(&(is_binary(&1) and String.contains?(&1, "Review finance")))

    assert finance_text =~ "<#{AtlasWeb.Endpoint.url()}/finance/vendors|Open source>"

    footer_text = blocks |> List.last() |> get_in(["elements", Access.at(0), "text"])
    assert footer_text == "Use the actions above to own, acknowledge, or tune these recommendations."
  end

  test "renders a finance-only brief as a joined, read-only financial update" do
    brief = insert_brief!()

    insert_item!(brief, "finance", "finance:runway", 1, %{
      kind: "risk",
      title: "Runway is below twelve months",
      detail: "Estimated runway is 7.16 months with EUR 259,063.33 available.",
      suggested_action: "Review the largest recent outflows.",
      completion_condition: "Leadership has reviewed the risk.",
      source_path: "/finance"
    })

    insert_item!(brief, "finance", "finance:cash-flow", 2, %{
      kind: "follow_up",
      title: "Review recent outflows",
      detail: "Review the largest recent outflows and committed renewals in Atlas.",
      source_path: "/finance"
    })

    subscription =
      brief.subscription
      |> Subscription.changeset(%{domains: ["finance"]})
      |> Repo.update!()

    brief = Repo.preload(%{brief | subscription: subscription}, [:subscription, items: [:owner]], force: true)
    blocks = Notifier.build_blocks(brief)
    text_blocks = Enum.map(blocks, &get_in(&1, ["text", "text"]))
    context_text = blocks |> Enum.flat_map(&Map.get(&1, "elements", [])) |> Enum.map(& &1["text"])
    findings = Enum.find(text_blocks, &(&1 && String.contains?(&1, "*What to watch*")))

    assert "*Financial pulse*\nAccounts and finance need attention." in text_blocks
    assert "2026-07-20 | Financial pulse" in context_text
    assert findings =~ "*What to watch*"
    assert findings =~ "*Runway is below twelve months*: Estimated runway is 7.16 months"
    assert findings =~ "*Suggested focus*"
    assert findings =~ "Review the largest recent outflows and committed renewals in Atlas."
    refute Enum.any?(blocks, &(&1["type"] == "actions"))
    refute findings =~ "Suggested next move"
    refute findings =~ "Done when"
    refute findings =~ "Owner:"
    refute findings =~ "Open source"
    refute "Use the actions above to own, acknowledge, or tune these recommendations." in text_blocks
  end

  test "renders a structured month-end finance recap with a dashboard link" do
    brief =
      insert_brief!(
        cadence: "monthly",
        period_start: ~U[2026-08-01 00:00:00Z],
        period_end: ~U[2026-09-01 00:00:00Z],
        headline: "August 2026: operating cash outflow of EUR 42,811.49",
        report: %{
          "kind" => "monthly_finance_recap",
          "intro" => "Cash received was EUR 36,055.00 and operating costs were EUR 78,866.49.",
          "sections" => [
            %{
              "heading" => "Monthly snapshot",
              "text" => "• *Closing cash:* EUR 260,411.58\n• *Estimated runway:* 8.2 months"
            },
            %{
              "heading" => "Recommended focus",
              "text" => "• Review the largest recurring operating costs."
            }
          ]
        }
      )

    blocks = Notifier.build_blocks(brief)
    text_blocks = Enum.map(blocks, &get_in(&1, ["text", "text"]))
    context_text = blocks |> Enum.flat_map(&Map.get(&1, "elements", [])) |> Enum.map(& &1["text"])

    assert "August 2026 | Month-end financial recap" in context_text
    assert "Cash received was EUR 36,055.00 and operating costs were EUR 78,866.49." in text_blocks
    assert "*Monthly snapshot*\n• *Closing cash:* EUR 260,411.58\n• *Estimated runway:* 8.2 months" in text_blocks
    assert "*Recommended focus*\n• Review the largest recurring operating costs." in text_blocks

    assert Enum.any?(blocks, fn
             %{"type" => "actions", "elements" => [%{"url" => url}]} -> url == "#{AtlasWeb.Endpoint.url()}/finance"
             _block -> false
           end)

    refute Enum.any?(blocks, &(&1["type"] == "actions" and get_in(&1, ["elements", Access.at(0), "action_id"])))
  end

  defp insert_brief!(attrs \\ []) do
    %Channel{slack_app: :company}
    |> Channel.changeset(%{channel_id: @slack_channel_id, channel_name: "leadership"})
    |> Repo.insert!()

    subscription =
      %Subscription{}
      |> Subscription.changeset(%{
        label: "Leadership daily",
        audience_key: "leadership-#{System.unique_integer([:positive])}",
        cadence: "daily",
        domains: ["accounts", "finance"],
        slack_app: "company",
        slack_channel_id: @slack_channel_id,
        max_sensitivity: "restricted",
        attention_budget: 8,
        enabled: true
      })
      |> Repo.insert!()

    defaults = %{
      cadence: "daily",
      period_start: ~U[2026-07-20 00:00:00Z],
      period_end: ~U[2026-07-21 00:00:00Z],
      status: "material",
      headline: "Daily leadership brief",
      summary: "Accounts and finance need attention.",
      attention_budget: 8,
      sensitivity: "internal",
      generation_mode: "deterministic"
    }

    brief =
      %Brief{brief_subscription_id: subscription.id}
      |> Brief.changeset(Map.merge(defaults, Map.new(attrs)))
      |> Repo.insert!()

    insert_item!(brief, "accounts", "account:default", 0)
    Repo.preload(brief, [:subscription, items: [:owner]], force: true)
  end

  defp insert_item!(brief, domain, fingerprint, position, attrs \\ %{}) do
    defaults = %{
      domain: domain,
      kind: "follow_up",
      title: "Review #{domain}",
      detail: "A current item needs attention.",
      severity: "warning",
      sensitivity: "internal",
      materiality_score: Decimal.new("0.82"),
      fingerprint: fingerprint,
      position: position,
      status: "open"
    }

    %BriefItem{brief_id: brief.id}
    |> BriefItem.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
