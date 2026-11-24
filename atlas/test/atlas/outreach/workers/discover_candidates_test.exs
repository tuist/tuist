defmodule Atlas.Outreach.Workers.DiscoverCandidatesTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.GTM.Outreach.Apollo
  alias Atlas.Outreach.Workers.DiscoverCandidates

  setup :verify_on_exit!

  test "records the discovery as a worker audit event" do
    stub(Apollo, :search_outreach_segment, fn segment_id, _opts ->
      {:ok, empty_segment_result(segment_id)}
    end)

    assert :ok = DiscoverCandidates.perform(%Oban.Job{})

    assert %Activity{interface: "worker"} =
             Repo.get_by!(Activity, action: "outreach.discovery_completed")
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
