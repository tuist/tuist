defmodule Symptoms.Labels do
  @moduledoc """
  Training labels from confirmed outcomes (README "Labels").

  `derive/2` runs after the state read-back for every symptom whose outcome
  changed:

  - **System-caused outcomes are recorded but excluded** (`independent:
    false`, with a `cause`): an investigation on the symptom or its root
    that the server marks `"reverted": true` (a mitigation step of it was
    taken; `revert_after_brief`); a `bad` outcome on a symptom that opened
    after it, or its root, was paged (`incident_after_page`), so the response
    to the page may have caused it; and any outcome, `bad` or `fine`, a
    person confirmed after that page (`confirmed_after_page`), which the page
    may have shaped either way. Only items confirmed before any page (during
    a delay) or never paged train, weighted as below. A page is a delivered
    one (`paged_at`); a page only logged with paging off is not.
  - **Weights** undo the random delay: a delayed item weighs `1 / q` and an
    item that could have been delayed but was not `1 / (1 - q)`, with `q` the
    recorded delay probability; an item that could not be delayed weighs 1.
    This inverse-propensity weighting is what lets a `bad` confirmed during a
    delay (before any page) stand for the paged items whose outcomes the
    page contaminated.
  - **Missed incident**: a `bad` outcome on a symptom that never reached
    board tier. An independent missed incident, or an independent `fine` on
    a symptom that paged, enqueues the event-triggered refit
    (`Symptoms.Calibrate`).
  - The outcome is attached to the symptom's snapshot (an `annotated`
    revision, a material change).

  `training_samples/2` returns the independent labels as Platt samples.
  """

  import Ecto.Query

  alias Symptoms.Log
  alias Symptoms.Repo
  alias Symptoms.Store
  alias Symptoms.Store.HumanEvent
  alias Symptoms.Store.HumanOutcome
  alias Symptoms.Store.Label
  alias Symptoms.Store.Symptom

  @tier_rank %{"audit" => 0, "board" => 1, "page" => 2}

  @doc "Derives labels for `symptom_ids` from their mirrored outcomes. Returns the labels written."
  @spec derive([String.t()], DateTime.t()) :: [Label.t()]
  def derive([], _now), do: []

  def derive(symptom_ids, now) do
    outcomes = Repo.all(from(o in HumanOutcome, where: o.symptom_id in ^symptom_ids))
    symptoms = Map.new(Repo.all(from(s in Symptom, where: s.id in ^symptom_ids)), &{&1.id, &1})

    labels =
      for outcome <- outcomes, sym = symptoms[outcome.symptom_id], sym != nil do
        label = label(sym, outcome, events(sym), page_at(sym, symptoms))

        Repo.insert_all(Label, [Map.merge(label, %{inserted_at: now, updated_at: now})],
          on_conflict: {:replace_all_except, [:symptom_id, :inserted_at]},
          conflict_target: [:symptom_id]
        )

        Store.audit("label", now,
          symptom_id: sym.id,
          data: Map.take(label, [:outcome, :independent, :cause, :weight, :missed, :score])
        )

        attach(sym, label, now)
        struct(Label, label)
      end

    if Enum.any?(labels, &refit_trigger?/1) do
      Oban.insert(Symptoms.Calibrate.new(%{"task" => "refit"}))
    end

    labels
  end

  @doc """
  The label for `symptom` given its mirrored `outcome`, the investigation
  events on it or its root, and `page_at`, when it or its root was first
  paged (`nil` if never). Pure.
  """
  @spec label(Symptom.t(), HumanOutcome.t(), [HumanEvent.t()], DateTime.t() | nil) :: map()
  def label(sym, outcome, events, page_at) do
    cause = cause(sym, outcome, events, page_at)
    q = sym.delay_probability || 0.0
    delayed = sym.delayed_until != nil
    weight = delay_weight(q, delayed)

    %{
      symptom_id: sym.id,
      outcome: outcome.outcome,
      independent: cause == nil,
      cause: cause,
      weight: weight,
      score: sym.max_score || 0.0,
      max_tier: sym.max_tier,
      missed: outcome.outcome == "bad" and @tier_rank[sym.max_tier || "audit"] < @tier_rank["board"],
      delay_probability: q,
      delayed: delayed,
      phenomena: (sym.document || %{})["phenomena"] || [],
      confirmed_at: outcome.confirmed_at
    }
  end

  defp cause(sym, outcome, events, page_at) do
    cond do
      reverted?(events) -> "revert_after_brief"
      after?(page_at, sym.opened_at) and outcome.outcome == "bad" -> "incident_after_page"
      after?(page_at, outcome.confirmed_at) -> "confirmed_after_page"
      true -> nil
    end
  end

  # The server sends an investigation's full state on every change, so only
  # its latest row (highest `change_seq`, per symptom) counts: a revert that
  # was undone no longer makes the outcome system-caused.
  defp reverted?(events) do
    events
    |> Enum.filter(&(&1.kind == "investigation"))
    |> Enum.group_by(& &1.symptom_id)
    |> Enum.any?(fn {_id, rows} -> Enum.max_by(rows, & &1.change_seq).data["reverted"] == true end)
  end

  # Whether `at` is after a page at `page_at` (never without a page). The
  # evidence started when the symptom opened: a symptom that opened in the
  # window its root paged did not start after the page.
  defp after?(nil, _at), do: false
  defp after?(page_at, at), do: DateTime.after?(at, page_at)

  # The earlier of the symptom's own page and its root's.
  defp page_at(sym, loaded) do
    root_id = get_in(sym.document || %{}, ["root", "root_symptom_id"])

    root_paged =
      cond do
        root_id in [nil, sym.id] -> nil
        root = loaded[root_id] -> root.paged_at
        true -> Repo.one(from(s in Symptom, where: s.id == ^root_id, select: s.paged_at))
      end

    [sym.paged_at, root_paged] |> Enum.reject(&is_nil/1) |> Enum.min(DateTime, fn -> nil end)
  end

  # Inverse-propensity weight for the recorded delay probability `q`.
  defp delay_weight(q, _delayed) when q <= 0 or q >= 1, do: 1.0
  defp delay_weight(q, true), do: 1 / q
  defp delay_weight(q, false), do: 1 / (1 - q)

  defp events(sym) do
    root = get_in(sym.document || %{}, ["root", "root_symptom_id"])
    ids = Enum.uniq(Enum.reject([sym.id, root], &is_nil/1))
    Repo.all(from(e in HumanEvent, where: e.symptom_id in ^ids))
  end

  defp refit_trigger?(%Label{independent: true, missed: true}), do: true
  defp refit_trigger?(%Label{independent: true, outcome: "fine", max_tier: "page"}), do: true
  defp refit_trigger?(_), do: false

  # The snapshot is read again under the log lock, so a revision committed
  # since `derive/2` loaded the symptom (a resolution) is the one annotated.
  defp attach(%Symptom{id: id}, label, now) do
    outcome = %{
      "outcome" => label.outcome,
      "confirmed_at" => DateTime.to_iso8601(label.confirmed_at),
      "independent" => label.independent,
      "cause" => label.cause
    }

    Repo.transaction(fn ->
      Log.lock!()
      sym = Repo.get!(Symptom, id)

      if sym.revision > 0 and sym.document["outcome"] != outcome do
        document =
          sym.document
          |> Map.drop(~w(seq revision schema_version symptom_id))
          |> Map.merge(%{"outcome" => outcome, "transition" => "annotated", "updated_at" => DateTime.to_iso8601(now)})

        Log.append!(sym, document, now)
      end
    end)
  end

  @doc """
  Independent labels confirmed since `since` as Platt samples `{score, bad?,
  weight}`, of the pipeline of `window_seconds` (its symptoms' root keys
  start with `"<window_seconds>:"`), or of every pipeline with `nil`.
  System-caused labels are never returned.
  """
  @spec training_samples(pos_integer() | nil, DateTime.t() | nil) :: [{float(), boolean(), float()}]
  def training_samples(window_seconds \\ nil, since \\ nil) do
    Label
    |> where([l], l.independent)
    |> then(fn query ->
      if window_seconds do
        join(query, :inner, [l], s in Symptom, on: s.id == l.symptom_id and like(s.root_key, ^"#{window_seconds}:%"))
      else
        query
      end
    end)
    |> then(&if(since, do: where(&1, [l], l.confirmed_at >= ^since), else: &1))
    |> select([l], {l.score, l.outcome == "bad", l.weight})
    |> Repo.all()
  end
end
