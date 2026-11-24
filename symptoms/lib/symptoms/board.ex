defmodule Symptoms.Board do
  @moduledoc """
  The daily board push (README "Decision"), an hourly Oban job that acts at
  09:00 Europe/Berlin, weekends included:

  1. Ranks the open root symptoms at board tier by `ln(expected cost)`.
  2. Draws each of the top five's random delay
     (`Symptoms.Decision.Policy.draw_delay/2`: 10–15 minutes with
     probability 0.2), stores it on the symptom (`delayed_until`,
     `delay_probability`, which `Symptoms.Labels` reweights by), writes an
     `annotated` revision with `"board" => %{"date", "rank", "nats",
     "delayed_until", "delay_probability"}` and records the push
     (`board_pushed` in the audit log). `GET /api/v1/symptoms/board` serves
     it until the next push, each item only once its delay has passed.
  3. Writes the daily digest of chronic Kubernetes reasons
     (`k8s_chronic_digest` in the audit log): per `(workload, reason)` the
     events counted in the last 24 hours. They never become evidence.
  """
  use Oban.Worker, queue: :calibration, max_attempts: 1, unique: [period: 3_600]

  import Ecto.Query

  alias Symptoms.Decision.Policy
  alias Symptoms.Log
  alias Symptoms.Repo
  alias Symptoms.Settings
  alias Symptoms.Store
  alias Symptoms.Store.AuditEvent
  alias Symptoms.Store.Symptom

  @size 5
  @candidates 20

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    # Oban's cron runs in UTC; the job runs hourly and pushes at 09:00 Berlin
    # (07:00 or 08:00 UTC with daylight saving).
    if DateTime.shift_zone!(now, "Europe/Berlin").hour == 9 do
      push(now)
      digest(now)
    end

    :ok
  end

  @doc "Pushes the board at `now`. Returns the pushed symptom ids in order."
  @spec push(DateTime.t()) :: [String.t()]
  def push(now) do
    ranked =
      @candidates
      |> Log.candidates()
      |> Enum.map(&%{id: &1["symptom_id"], score: base_score(&1)})
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(@size)

    date = now |> DateTime.shift_zone!("Europe/Berlin") |> DateTime.to_date() |> Date.to_iso8601()

    policy = Settings.policy_opts()

    ranked
    |> Enum.with_index(1)
    |> Enum.each(fn {item, rank} -> mark(item, rank, date, Policy.draw_delay(now, policy), now) end)

    ids = Enum.map(ranked, & &1.id)
    Store.audit("board_pushed", now, data: %{date: date, symptom_ids: ids})
    ids
  end

  defp base_score(document) do
    cost = Repo.one(from(s in Symptom, where: s.id == ^document["symptom_id"], select: s.expected_cost)) || 0.0
    :math.log(max(cost, 1.0e-9))
  end

  defp mark(item, rank, date, {delayed_until, probability}, now) do
    Repo.transaction(fn ->
      Log.lock!()

      Repo.update_all(from(s in Symptom, where: s.id == ^item.id),
        set: [delayed_until: delayed_until, delay_probability: probability]
      )

      symptom = Repo.get!(Symptom, item.id)

      document =
        symptom.document
        |> Map.drop(~w(seq revision schema_version symptom_id))
        |> Map.merge(%{
          "board" => %{
            "date" => date,
            "rank" => rank,
            "nats" => Float.round(item.score * 1.0, 4),
            "delayed_until" => delayed_until && DateTime.to_iso8601(delayed_until),
            "delay_probability" => probability
          },
          "transition" => "annotated",
          "updated_at" => DateTime.to_iso8601(now)
        })

      Log.append!(symptom, document, now)
    end)
  end

  @doc """
  The daily digest of chronic Kubernetes reasons from the last 24 hours of
  `k8s_chronic` audit events. Returns `[%{"entity", "count"}]`.
  """
  @spec digest(DateTime.t()) :: [map()]
  def digest(now) do
    since = DateTime.shift(now, day: -1)

    items =
      from(a in AuditEvent, where: a.kind == "k8s_chronic" and a.at > ^since and a.at <= ^now, select: a.data)
      |> Repo.all()
      |> Enum.flat_map(&(&1["items"] || []))
      |> Enum.group_by(& &1["entity"], & &1["count"])
      |> Enum.map(fn {entity, counts} -> %{"entity" => entity, "count" => Enum.sum(counts)} end)
      |> Enum.sort_by(&(-&1["count"]))

    Store.audit("k8s_chronic_digest", now, data: %{items: items})
    items
  end
end
