defmodule Atlas.Outreach.Workers.DiscoverCandidatesTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.GTM.Outreach.Apollo
  alias Atlas.Outreach.Candidate
  alias Atlas.Outreach.CandidateNotifier
  alias Atlas.Outreach.Workers.DiscoverCandidates

  setup :verify_on_exit!

  test "announces pending candidates and records worker audit events" do
    candidate = insert_pending_candidate!()

    expect(CandidateNotifier, :notify, fn announced ->
      assert announced.id == candidate.id
      {:ok, %{channel_id: "C_SALES", thread_ts: "1717400000.000100"}}
    end)

    stub(Apollo, :search_outreach_segment, fn segment_id, _opts ->
      {:ok, empty_segment_result(segment_id)}
    end)

    assert :ok = DiscoverCandidates.perform(%Oban.Job{})

    notified = Repo.get!(Candidate, candidate.id)
    assert %DateTime{} = notified.slack_notification_posted_at
    assert notified.slack_notification_channel_id == "C_SALES"
    assert notified.slack_notification_thread_ts == "1717400000.000100"

    assert %Activity{interface: "worker"} =
             Repo.get_by!(Activity, action: "outreach.candidate_notified", target_id: candidate.id)

    assert %Activity{interface: "worker"} =
             Repo.get_by!(Activity, action: "outreach.discovery_completed")
  end

  test "returns notification failures so the job can retry before searching again" do
    candidate = insert_pending_candidate!()

    expect(CandidateNotifier, :notify, fn announced ->
      assert announced.id == candidate.id
      {:error, :slack_down}
    end)

    reject(Apollo, :search_outreach_segment, 2)

    assert {:error, :slack_down} = DiscoverCandidates.perform(%Oban.Job{})
    assert Repo.get!(Candidate, candidate.id).slack_notification_posted_at == nil
  end

  defp insert_pending_candidate! do
    %Candidate{slack_notification_requested_at: ~U[2026-07-20 12:00:00Z]}
    |> Candidate.changeset(%{
      source: "apollo",
      source_id: "daily-candidate-#{System.unique_integer([:positive])}",
      search_segment: "mobile_mid_large",
      search_version: 1,
      status: "pending",
      full_name: "Riley Stone",
      title: "Head of Mobile",
      organization_name: "Search Platforms",
      organization_domain: "search.example",
      linkedin_url: "https://www.linkedin.com/in/riley-stone",
      search_rank: 1,
      discovered_at: ~U[2026-07-20 12:00:00Z]
    })
    |> Repo.insert!()
  end

  defp empty_segment_result(segment_id) do
    %{
      segment: %{id: segment_id, name: segment_id, version: 1},
      people: [],
      total: 0,
      excluded: 0,
      definition: %{}
    }
  end
end
