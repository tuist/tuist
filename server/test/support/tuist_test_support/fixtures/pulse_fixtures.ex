defmodule TuistTestSupport.Fixtures.PulseFixtures do
  @moduledoc false

  @doc """
  A symptom log revision as the evaluator serves it (`symptoms/README.md`,
  "Symptom log"). String-keyed overrides replace top-level fields.
  """
  def symptom_revision(overrides \\ %{}) do
    Map.merge(
      %{
        "schema_version" => "1.0",
        "seq" => 1,
        "symptom_id" => "0193a1f0-0000-7000-8000-000000000001",
        "symptom_key" => String.duplicate("a", 64),
        "scope" => %{"kind" => "tuist_ops"},
        "revision" => 1,
        "state" => "open",
        "merged_into" => nil,
        "tier" => "board",
        "transition" => "opened",
        "entity" => %{
          "environment" => "production",
          "service" => "tuist-server",
          "kind" => "route",
          "key" => "POST /api/runs"
        },
        "title" => "Errors on POST /api/runs",
        "phenomena" => [
          %{"phenomenon" => "request_errors", "nats" => 2.4, "sources" => ["trace.error_betabinomial"]},
          %{"phenomenon" => "latency", "nats" => 1.1, "sources" => ["trace.latency_exceedance"]}
        ],
        "score" => 6.1,
        "p_degraded" => 0.42,
        "impact" => %{"unit" => "failed_requests_per_min", "rate" => 12.0},
        "budget_price" => 3.5,
        "decision" => %{"tier" => "board", "would_page" => false, "delayed_until" => nil, "delay_probability" => 0.2},
        "root" => %{"root_symptom_id" => nil, "member_symptom_ids" => [], "shared_cause" => false},
        "suspected_change" => nil,
        "evidence" => %{"series_refs" => [], "example_ids" => [], "masked_excerpts" => []},
        "brief_ref" => nil,
        "outcome" => nil,
        "opened_at" => "2026-11-16T12:00:00Z",
        "updated_at" => "2026-11-16T12:00:00Z",
        "resolved_at" => nil
      },
      overrides
    )
  end

  @doc """
  Serves `revisions` as the evaluator's log (those after the requested `seq`)
  and runs `Tuist.Pulse.Symptoms.sync/1`, so tests build the mirror the way
  production does. Returns the sync result.
  """
  def mirror_symptoms(account, revisions) do
    Mimic.stub(Tuist.Environment, :symptoms_config, fn ->
      [base_url: "https://symptoms.internal", token: "log-token"]
    end)

    Mimic.stub(Req, :get, fn
      "https://symptoms.internal/api/v1/symptoms/log", opts ->
        after_seq = opts[:params][:after]
        body = %{"revisions" => Enum.filter(revisions, &(&1["seq"] > after_seq)), "next" => after_seq}
        {:ok, %Req.Response{status: 200, body: body}}

      url, opts ->
        Mimic.call_original(Req, :get, [url, opts])
    end)

    Tuist.Pulse.Symptoms.sync(account)
  end
end
