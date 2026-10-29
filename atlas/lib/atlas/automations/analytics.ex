defmodule Atlas.Automations.Analytics do
  @moduledoc "Bounded UTC execution cohorts, aggregated in PostgreSQL without loading run payloads."

  import Ecto.Query

  alias Atlas.Automations
  alias Atlas.Automations.DomainAccess
  alias Atlas.Automations.Revision
  alias Atlas.Automations.Run
  alias Atlas.Repo

  @terminal ~w(succeeded failed rejected cancelled)
  @counts ~w(executions succeeded failed rejected cancelled waiting_approval active duration_samples)a

  def get(actor, params \\ %{}) do
    with :ok <- Automations.authorize(actor, :read),
         {:ok, days} <- days(Map.get(params, "days", 30)),
         {:ok, until} <- end_date(params["end_date"]),
         :ok <- workflow_access(actor, params["workflow_id"]) do
      first = Date.add(until, 1 - days)
      previous_first = Date.add(first, -days)
      rows = daily_rows(actor, params["workflow_id"], previous_first, until)
      {current, previous} = Enum.split_with(rows, &(Date.compare(&1.date, first) != :lt))
      by_date = Map.new(current, &{&1.date, &1})

      {:ok,
       %{
         days: days,
         from: Date.to_iso8601(first),
         until: Date.to_iso8601(until),
         timezone: "UTC",
         workflow_id: params["workflow_id"],
         total: summarize(current),
         previous: summarize(previous),
         points:
           Enum.map(Date.range(first, until), fn date ->
             by_date |> Map.get(date, empty()) |> measurements() |> Map.put(:date, Date.to_iso8601(date))
           end)
       }}
    end
  end

  def runs_query(actor, params) do
    with :ok <- Automations.authorize(actor, :read),
         :ok <- workflow_access(actor, params["workflow_id"]) do
      query = params["workflow_id"] |> base_query() |> DomainAccess.scope(actor)

      if Map.has_key?(params, "days") or Map.has_key?(params, "end_date") do
        with {:ok, days} <- days(Map.get(params, "days", 30)),
             {:ok, until} <- end_date(params["end_date"]) do
          {:ok, period_query(query, Date.add(until, 1 - days), until)}
        end
      else
        {:ok, query}
      end
    end
  end

  defp days(value) when is_integer(value) and value in 1..90, do: {:ok, value}

  defp days(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> days(number)
      _ -> {:error, :invalid_period}
    end
  end

  defp days(_), do: {:error, :invalid_period}
  defp end_date(nil), do: {:ok, Date.utc_today()}

  defp end_date(value) when is_binary(value) do
    with {:ok, date} <- Date.from_iso8601(value),
         true <- date.year > 0 and Date.compare(date, Date.utc_today()) != :gt do
      {:ok, date}
    else
      _ -> {:error, :invalid_period}
    end
  end

  defp end_date(_), do: {:error, :invalid_period}
  defp workflow_access(_actor, nil), do: :ok

  defp workflow_access(actor, id) do
    with {:ok, _} <- Automations.get_workflow(actor, id), do: :ok
  end

  defp base_query(workflow_id) do
    query = from(r in Run, join: revision in Revision, on: revision.id == r.revision_id)
    if workflow_id, do: where(query, [_r, revision], revision.workflow_id == ^workflow_id), else: query
  end

  defp period_query(query, first, until) do
    start_at = DateTime.new!(first, ~T[00:00:00], "Etc/UTC")
    end_at = DateTime.new!(Date.add(until, 1), ~T[00:00:00], "Etc/UTC")
    now = DateTime.utc_now()
    where(query, [r], r.inserted_at >= ^start_at and r.inserted_at < ^end_at and r.inserted_at <= ^now)
  end

  defp daily_rows(actor, workflow_id, first, until) do
    query = workflow_id |> base_query() |> DomainAccess.scope(actor) |> period_query(first, until)

    query =
      from([r, _revision] in query,
        group_by: fragment("(? AT TIME ZONE 'UTC')::date", r.inserted_at),
        select: %{
          date: type(fragment("(? AT TIME ZONE 'UTC')::date", r.inserted_at), :date),
          executions: count(r.id),
          succeeded: filter(count(r.id), r.status == "succeeded"),
          failed: filter(count(r.id), r.status == "failed"),
          rejected: filter(count(r.id), r.status == "rejected"),
          cancelled: filter(count(r.id), r.status == "cancelled"),
          waiting_approval: filter(count(r.id), r.status == "waiting_approval"),
          active: filter(count(r.id), r.status in ["queued", "running", "waiting_approval"]),
          duration_samples:
            filter(
              count(r.id),
              r.status in ^@terminal and not is_nil(r.completed_at) and r.completed_at >= r.inserted_at
            ),
          duration_seconds:
            coalesce(
              filter(
                sum(type(fragment("EXTRACT(EPOCH FROM (? - ?))", r.completed_at, r.inserted_at), :float)),
                r.status in ^@terminal and not is_nil(r.completed_at) and r.completed_at >= r.inserted_at
              ),
              0.0
            )
        }
      )

    Repo.all(query)
  end

  defp empty, do: @counts |> Map.new(&{&1, 0}) |> Map.put(:duration_seconds, 0.0)

  defp summarize(rows) do
    rows
    |> Enum.reduce(empty(), fn row, total ->
      Map.new(total, fn {key, value} -> {key, value + Map.fetch!(row, key)} end)
    end)
    |> measurements()
  end

  defp measurements(row) do
    finished = row.succeeded + row.failed + row.rejected + row.cancelled

    row
    |> Map.delete(:duration_seconds)
    |> Map.put(:finished, finished)
    |> Map.put(:success_rate, ratio(row.succeeded * 100, finished))
    |> Map.put(:average_completion_seconds, ratio(row.duration_seconds, row.duration_samples))
  end

  defp ratio(_, 0), do: nil
  defp ratio(numerator, denominator), do: numerator / denominator
end
