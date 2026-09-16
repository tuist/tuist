defmodule Atlas.Finance.Briefs.SlackRendererTest do
  use ExUnit.Case, async: true

  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Notifier
  alias Atlas.Briefs.Subscription
  alias Atlas.Finance.Briefs.SlackRenderer

  test "publishes the narrative once with supported headings, paragraphs, and a dashboard link" do
    brief = brief()
    blocks = Notifier.build_blocks(brief)
    text = block_text(blocks)

    assert text =~ "2026-09-07 to 2026-09-13"
    assert text =~ "*Key factors driving the numbers*"
    assert text =~ "*Hardware purchases*"
    assert text =~ "Mol∗Vendor &amp; Co"
    assert text =~ "&lt;!channel&gt;"
    assert text =~ "*What to watch*"
    assert text =~ "*Recommended next steps*"
    assert length(Regex.scan(~r/Confirm the purchase is a one-off\./, text)) == 1
    assert text =~ "<#{AtlasWeb.Endpoint.url()}/commercial/finance|Explore the finance dashboard>"
    refute text =~ "Duplicate task detail"
    refute text =~ "**"
    refute text =~ "Automated snapshot"
    assert text =~ "Spending increased this week.\n\nCash covers eight months."
  end

  test "identifies fallback output without exposing internal error details" do
    brief = brief()
    brief = %{brief | report: Map.put(brief.report, "generation_mode", "deterministic_fallback")}
    assert block_text(SlackRenderer.build_blocks(brief)) =~ "agent analysis was unavailable"
  end

  test "splits long and heavily escaped copy within Slack section limits" do
    brief = brief()
    prose = String.duplicate("<&>", 1500)
    brief = %{brief | report: Map.put(brief.report, "intro", prose)}

    blocks = SlackRenderer.build_blocks(brief)

    for %{"type" => "section", "text" => %{"text" => text}} <- blocks do
      assert String.length(text) <= 3000
      refute text =~ ~r/&(?:a|am|amp|l|lt|g|gt)?$/
    end

    assert block_text(blocks) =~ "&lt;&amp;&gt;"
  end

  defp block_text(blocks) do
    Enum.map_join(blocks, "\n", fn block ->
      get_in(block, ["text", "text"]) ||
        Enum.map_join(Map.get(block, "elements", []), "\n", & &1["text"])
    end)
  end

  defp brief do
    %Brief{
      headline: "Weekly financial pulse",
      period_start: ~U[2026-09-07 00:00:00Z],
      period_end: ~U[2026-09-14 00:00:00Z],
      subscription: %Subscription{domains: ["finance"]},
      items: [%BriefItem{detail: "Duplicate task detail"}],
      report: %{
        "kind" => "finance_pulse",
        "generation_mode" => "agent",
        "intro" => "Spending increased this week.\n\nCash covers eight months.",
        "drivers" => [
          %{"title" => "Hardware purchases", "detail" => "Mol*Vendor & Co recorded a debit. <!channel>"}
        ],
        "concerns" => [%{"title" => "Runway", "detail" => "Less than twelve months remain."}],
        "next_steps" => ["Confirm the purchase is a one-off."]
      }
    }
  end
end
