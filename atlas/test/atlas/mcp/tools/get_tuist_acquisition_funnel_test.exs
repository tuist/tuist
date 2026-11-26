defmodule Atlas.MCP.Tools.GetTuistAcquisitionFunnelTest do
  use Atlas.MCP.ToolCase

  import Mimic

  alias Atlas.MCP.Tools.GetTuistAcquisitionFunnel
  alias Atlas.TuistAcquisition
  alias Atlas.TuistServer

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "returns the funnel for a range and source as JSON" do
    stub(TuistServer, :configured?, fn -> true end)

    expect(TuistAcquisition, :funnel, fn {~D[2026-09-01], ~D[2026-09-02]}, opts ->
      assert opts[:source] == "chatgpt.com"
      assert opts[:campaign] == "hub"
      points = fn values -> Enum.zip([~D[2026-09-01], ~D[2026-09-02]], values) end

      {:ok,
       %{
         granularity: :day,
         totals: %{landings: 30, signups: 3, attributed_signups: 3, customers: 1},
         previous: %{landings: 10, signups: 1, attributed_signups: 1, customers: 0},
         sources: ["chatgpt.com", "newsletter"],
         campaigns: [%{campaign: "hub", sources: ["chatgpt.com"], ads: [], landings: 30, signups: 3, customers: 1}],
         effectiveness: %{signup_rate: 0.1, first_active_on: ~D[2026-09-01], plans: %{"pro" => 1}},
         subscriptions: [
           %{
             account: "acme",
             plan: "pro",
             status: "active",
             subscribed_on: ~D[2026-09-02],
             signed_up_on: ~D[2026-09-01],
             source: "chatgpt.com",
             medium: "",
             campaign: "hub",
             content: "ad-42"
           }
         ],
         channels: [
           %{source: "chatgpt.com", medium: "", campaign: "hub", content: "", landings: 30, signups: 3, customers: 1}
         ],
         series: %{
           landings: points.([10, 20]),
           signups: points.([1, 2]),
           attributed_signups: points.([1, 2]),
           customers: points.([0, 1])
         }
       }}
    end)

    assert {:ok, result} =
             execute_tool(GetTuistAcquisitionFunnel, %{}, %{
               "start_date" => "2026-09-01",
               "end_date" => "2026-09-02",
               "source" => "ChatGPT.com",
               "campaign" => "hub"
             })

    assert result["totals"]["landings"] == 30
    assert result["previous_totals"]["landings"] == 10
    assert result["sources"] == ["chatgpt.com", "newsletter"]
    assert [%{"campaign" => "hub", "signups" => 3}] = result["campaigns"]

    assert %{"signup_rate" => 0.1, "first_active_on" => "2026-09-01", "plans" => %{"pro" => 1}} =
             result["effectiveness"]

    assert [%{"account" => "acme", "content" => "ad-42", "subscribed_on" => "2026-09-02"}] = result["subscriptions"]
    assert [%{"campaign" => "hub", "customers" => 1}] = result["channels"]

    assert List.last(result["series"]) == %{
             "date" => "2026-09-02",
             "landings" => 20,
             "signups" => 2,
             "attributed_signups" => 2,
             "customers" => 1
           }
  end

  test "rejects an inverted or missing range" do
    stub(TuistServer, :configured?, fn -> true end)

    assert {:error, "start_date and end_date must be" <> _rest} =
             execute_tool(GetTuistAcquisitionFunnel, %{}, %{"start_date" => "2026-09-02", "end_date" => "2026-09-01"})

    assert {:error, "start_date and end_date are required."} = execute_tool(GetTuistAcquisitionFunnel, %{}, %{})
  end

  test "says when the Tuist server is unreachable" do
    assert {:error, "The Tuist server database is not reachable from this environment."} =
             execute_tool(GetTuistAcquisitionFunnel, %{}, %{"start_date" => "2026-09-01", "end_date" => "2026-09-02"})
  end
end
