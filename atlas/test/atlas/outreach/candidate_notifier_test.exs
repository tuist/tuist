defmodule Atlas.Outreach.CandidateNotifierTest do
  use Atlas.DataCase, async: true

  alias Atlas.Outreach.Candidate
  alias Atlas.Outreach.CandidateNotifier

  test "builds a rich candidate message without exposing the discovery provider" do
    candidate = candidate()
    blocks = CandidateNotifier.build_blocks(candidate)
    rendered = JSON.encode!(blocks)

    assert rendered =~ "New outreach candidate"
    assert rendered =~ "Riley Stone"
    assert rendered =~ "Head of Mobile"
    assert rendered =~ "Search Platforms"
    assert rendered =~ "United States"
    assert rendered =~ "Open LinkedIn"
    assert rendered =~ "Review in Atlas"
    refute rendered =~ "Apollo"
  end

  test "posts one candidate to the configured sales channel with an idempotency key" do
    candidate = candidate()

    poster = fn :company, "C_SALES", text, blocks, opts ->
      assert text =~ "Riley Stone"
      assert is_list(blocks)
      assert opts[:client_msg_id] == candidate.id
      {:ok, %{"channel" => "C_SALES", "ts" => "1717400000.000100"}}
    end

    assert {:ok, %{channel_id: "C_SALES", thread_ts: "1717400000.000100"}} =
             CandidateNotifier.notify(candidate,
               outreach_config: [candidate_slack_channel_id: "C_SALES"],
               poster: poster
             )
  end

  test "does not post without a configured sales channel" do
    assert {:error, :outreach_candidate_slack_channel_not_configured} =
             CandidateNotifier.notify(candidate(), outreach_config: [])
  end

  defp candidate do
    %Candidate{
      id: Ecto.UUID.generate(),
      full_name: "Riley Stone",
      title: "Head of Mobile",
      organization_name: "Search Platforms",
      linkedin_url: "https://www.linkedin.com/in/riley-stone",
      search_segment: "mobile_mid_large",
      search_rank: 4,
      metadata: %{"city" => "New York", "country" => "United States"}
    }
  end
end
