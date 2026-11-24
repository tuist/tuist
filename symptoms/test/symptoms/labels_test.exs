defmodule Symptoms.LabelsTest do
  use Symptoms.DataCase
  use Oban.Testing, repo: Symptoms.Repo

  alias Symptoms.Labels
  alias Symptoms.Log
  alias Symptoms.State
  alias Symptoms.Store.HumanAck
  alias Symptoms.Store.HumanMute
  alias Symptoms.Store.HumanOutcome
  alias Symptoms.Store.Label
  alias Symptoms.Store.Symptom

  @at ~U[2026-11-16 10:00:00.000000Z]

  defp symptom(attrs) do
    Repo.insert!(
      struct(
        %Symptom{
          id: Log.uuid7(@at),
          symptom_key: "k",
          root_key: "60:entity:1",
          phenomenon: "request_errors",
          state: "resolved",
          tier: "audit",
          max_tier: "audit",
          opened_at: @at
        },
        attrs
      )
    )
  end

  defp outcome(sym, outcome, seq, at \\ DateTime.shift(@at, hour: 1)) do
    %{"symptom_id" => sym.id, "outcome" => outcome, "confirmed_at" => DateTime.to_iso8601(at), "change_seq" => seq}
  end

  test "trains only on independent outcomes, weighted by the recorded delay probability" do
    # Opened at @at and confirmed at @at + 30 s, both before the page at
    # @at + 1 min, so the page cannot have caused it: trained on. Not delayed
    # with q = 0.2: weight 1.25.
    paged = symptom(max_tier: "page", max_score: 9.0, paged_at: DateTime.shift(@at, minute: 1), delay_probability: 0.2)
    # Its investigation was reverted after the brief: recorded, not trained on.
    reverted = symptom(max_tier: "board", max_score: 7.0)
    # Delayed board item (q = 0.2): weight 1 / 0.2 = 5.
    delayed =
      symptom(max_tier: "board", max_score: 6.5, delay_probability: 0.2, delayed_until: DateTime.shift(@at, minute: 10))

    # Could have been delayed but was not: weight 1 / (1 − 0.2) = 1.25.
    undelayed = symptom(max_tier: "board", max_score: 6.2, delay_probability: 0.2)
    # Bad that never reached the board: a missed incident, weight 1.
    missed = symptom(max_tier: "audit", max_score: 2.0)

    body = %{
      "acks" => [],
      "mutes" => [],
      "investigations" => [%{"symptom_id" => reverted.id, "reverted" => true, "change_seq" => 1}],
      "outcomes" => [
        outcome(paged, "bad", 2, DateTime.shift(@at, second: 30)),
        outcome(reverted, "fine", 3),
        outcome(delayed, "fine", 4),
        outcome(undelayed, "bad", 5),
        outcome(missed, "bad", 6)
      ],
      "next" => 6
    }

    # 1 investigation + 5 outcomes.
    assert {6, ids, 6} = State.apply_page(body, 0, @at)
    assert length(ids) == 5
    assert State.cursor() == 6

    labels = Map.new(Repo.all(Label), &{&1.symptom_id, &1})
    assert %{independent: true, cause: nil, weight: 1.25} = labels[paged.id]
    assert %{independent: false, cause: "revert_after_brief"} = labels[reverted.id]
    assert %{independent: true, weight: 5.0, delayed: true} = labels[delayed.id]
    assert %{independent: true, weight: 1.25} = labels[undelayed.id]
    assert %{independent: true, missed: true, weight: 1.0} = labels[missed.id]

    assert Enum.sort(Labels.training_samples()) ==
             [{2.0, true, 1.0}, {6.2, true, 1.25}, {6.5, false, 5.0}, {9.0, true, 1.25}]

    # The missed incident triggers the bounded refit.
    assert_enqueued(worker: Symptoms.Calibrate, args: %{"task" => "refit"})
  end

  test "a bad outcome before the page was delivered is independent" do
    sym = symptom(max_tier: "page", max_score: 8.0, paged_at: DateTime.shift(@at, hour: 2))
    State.apply_page(%{"outcomes" => [outcome(sym, "bad", 1)], "next" => 1}, 0, @at)

    assert %{independent: true, cause: nil} = Repo.get!(Label, sym.id)
  end

  test "a bad outcome is system-caused when its evidence started after the page" do
    # The root opened at @at and paged at @at + 1 min; the person confirmed
    # the root and the member that joined with it at @at + 30 s, before the
    # page.
    root = symptom(max_tier: "page", max_score: 9.0, paged_at: DateTime.shift(@at, minute: 1))
    root_doc = %{"root" => %{"root_symptom_id" => root.id}}
    # A member that joined in the same window as the page: its evidence did
    # not start after the page.
    same = symptom(max_tier: "page", max_score: 8.0, document: root_doc)
    # A member whose evidence started 5 minutes after its root paged: the
    # response to the page may have caused it.
    later = symptom(max_tier: "page", max_score: 7.0, opened_at: DateTime.shift(@at, minute: 5), document: root_doc)

    before_page = DateTime.shift(@at, second: 30)

    body = %{
      "outcomes" => [
        outcome(root, "bad", 1, before_page),
        outcome(same, "bad", 2, before_page),
        outcome(later, "bad", 3, DateTime.shift(@at, minute: 6))
      ],
      "next" => 3
    }

    State.apply_page(body, 0, @at)

    assert %{independent: true, cause: nil} = Repo.get!(Label, root.id)
    assert %{independent: true, cause: nil} = Repo.get!(Label, same.id)
    assert %{independent: false, cause: "incident_after_page"} = Repo.get!(Label, later.id)
  end

  test "an investigation reverted after the outcome re-derives the labels of its root and members" do
    root = symptom(max_tier: "board", max_score: 7.0)
    member = symptom(max_tier: "board", max_score: 6.0, document: %{"root" => %{"root_symptom_id" => root.id}})

    State.apply_page(%{"outcomes" => [outcome(root, "bad", 1), outcome(member, "bad", 2)], "next" => 2}, 0, @at)
    assert %{independent: true} = Repo.get!(Label, root.id)
    assert %{independent: true} = Repo.get!(Label, member.id)

    # The row as `Tuist.Pulse.Investigations.state_rows/1` sends it once a
    # mitigation step of the investigation was taken.
    investigation = %{
      "symptom_id" => root.id,
      "member_symptom_ids" => [member.id],
      "trigger" => "opened",
      "status" => "completed",
      "thread_id" => "T-1",
      "brief_id" => 1,
      "brief_revision" => 1,
      "steps_taken" => [%{"step_id" => 3, "section" => "mitigate", "kind" => "rollback", "status" => "taken"}],
      "reverted" => true,
      "change_seq" => 3
    }

    assert {1, [], 3} = State.apply_page(%{"investigations" => [investigation], "next" => 3}, 2, @at)
    assert %{independent: false, cause: "revert_after_brief"} = Repo.get!(Label, root.id)
    assert %{independent: false, cause: "revert_after_brief"} = Repo.get!(Label, member.id)
  end

  test "only an investigation's latest row decides whether it reverted" do
    sym = symptom(max_tier: "board", max_score: 7.0)
    row = fn reverted, seq -> %{"symptom_id" => sym.id, "reverted" => reverted, "change_seq" => seq} end

    State.apply_page(%{"investigations" => [row.(true, 1)], "outcomes" => [outcome(sym, "bad", 2)], "next" => 2}, 0, @at)
    assert %{independent: false, cause: "revert_after_brief"} = Repo.get!(Label, sym.id)

    # The step was undone: the server's latest row says not reverted.
    State.apply_page(%{"investigations" => [row.(false, 3)], "next" => 3}, 2, @at)
    assert %{independent: true, cause: nil} = Repo.get!(Label, sym.id)
  end

  test "an outcome a person confirmed after the page never trains, bad or fine" do
    paged_at = DateTime.shift(@at, minute: 1)
    bad = symptom(max_tier: "page", max_score: 9.0, paged_at: paged_at)
    fine = symptom(max_tier: "page", max_score: 8.0, paged_at: paged_at)
    # Confirmed during its delay, before any page: trains.
    early = symptom(max_tier: "page", max_score: 8.5, paged_at: paged_at)

    body = %{
      "outcomes" => [
        outcome(bad, "bad", 1),
        outcome(fine, "fine", 2),
        outcome(early, "fine", 3, DateTime.shift(@at, second: 30))
      ],
      "next" => 3
    }

    State.apply_page(body, 0, @at)

    # bad and fine opened at @at, before the page, and were confirmed an hour
    # later: the page may have shaped either confirmation.
    assert %{independent: false, cause: "confirmed_after_page"} = Repo.get!(Label, bad.id)
    assert %{independent: false, cause: "confirmed_after_page"} = Repo.get!(Label, fine.id)
    assert %{independent: true, cause: nil} = Repo.get!(Label, early.id)
  end

  test "mutes, acks and the cursor are mirrored; a stale next never moves the cursor back" do
    entity = %{"environment" => "production", "service" => "s", "kind" => "route", "key" => "GET /"}
    expires = DateTime.to_iso8601(DateTime.shift(@at, hour: 1))

    body = %{
      "acks" => [
        %{"symptom_id" => Log.uuid7(@at), "revision" => 2, "acked_at" => DateTime.to_iso8601(@at), "change_seq" => 7}
      ],
      "mutes" => [%{"entity" => entity, "phenomenon" => "latency", "expires_at" => expires, "change_seq" => 8}],
      "next" => 8
    }

    assert {2, [], 8} = State.apply_page(body, 0, @at)
    assert {0, [], 8} = State.apply_page(%{"next" => 3}, 8, @at)
    assert State.cursor() == 8
    assert [%{phenomenon: "latency", key: "GET /"}] = Repo.all(HumanMute)
  end

  test "state read-back accepts server timestamps and preserves fractional seconds" do
    for {timestamp, microseconds} <- [
          {"2026-11-16T10:00:00Z", 0},
          {"2026-11-16T10:00:00.123Z", 123_000},
          {"2026-11-16T10:00:00.123456Z", 123_456}
        ] do
      sym = symptom([])
      cursor = State.cursor()
      entity = %{"environment" => "production", "service" => "s", "kind" => "route", "key" => timestamp}

      body = %{
        "acks" => [%{"symptom_id" => sym.id, "revision" => 2, "acked_at" => timestamp, "change_seq" => cursor + 1}],
        "mutes" => [
          %{"entity" => entity, "phenomenon" => "latency", "expires_at" => timestamp, "change_seq" => cursor + 2}
        ],
        "outcomes" => [
          %{"symptom_id" => sym.id, "outcome" => "fine", "confirmed_at" => timestamp, "change_seq" => cursor + 3}
        ],
        "next" => cursor + 3
      }

      assert {3, [id], next} = State.apply_page(body, cursor, @at)
      assert id == sym.id
      assert next == cursor + 3
      assert Repo.get!(HumanAck, id).acked_at.microsecond == {microseconds, 6}
      assert Repo.get!(HumanOutcome, id).confirmed_at.microsecond == {microseconds, 6}
      assert Repo.get_by!(HumanMute, key: timestamp).expires_at.microsecond == {microseconds, 6}
    end
  end

  test "an older in-flight state page cannot undo newer human state or labels" do
    sym = symptom(max_score: 7.0)
    entity = %{"environment" => "production", "service" => "s", "kind" => "route", "key" => "GET /"}
    newer_expiry = DateTime.shift(@at, week: 1)
    older_expiry = DateTime.shift(@at, hour: 1)

    page = fn seq, revision, result, expiry ->
      %{
        "acks" => [
          %{"symptom_id" => sym.id, "revision" => revision, "acked_at" => DateTime.to_iso8601(@at), "change_seq" => seq}
        ],
        "mutes" => [
          %{
            "entity" => entity,
            "phenomenon" => "latency",
            "expires_at" => DateTime.to_iso8601(expiry),
            "change_seq" => seq + 1
          }
        ],
        "outcomes" => [outcome(sym, result, seq + 2)],
        "next" => seq + 2
      }
    end

    assert {3, [_], 6} = State.apply_page(page.(4, 2, "fine", newer_expiry), 0, @at)
    # Both requests left with cursor 0, but the older response arrives last.
    assert {0, [], 6} = State.apply_page(page.(1, 1, "bad", older_expiry), 0, @at)
    assert State.cursor() == 6
    assert Repo.get!(HumanAck, sym.id).revision == 2
    assert Repo.one!(HumanMute).expires_at == newer_expiry
    assert Repo.get!(HumanOutcome, sym.id).outcome == "fine"
    assert Repo.get!(Label, sym.id).outcome == "fine"

    assert {3, [_], 9} = State.apply_page(page.(7, 3, "bad", newer_expiry), 6, @at)
    assert Repo.get!(HumanOutcome, sym.id).outcome == "bad"
  end
end
