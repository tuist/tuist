defmodule Tuist.OnceEvents.Workers.PublishTestReportWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :once_test_reports,
    max_attempts: 8,
    unique: [period: 600, keys: [:run_id, :phase], states: [:available, :scheduled, :retryable, :executing]]

  import Ecto.Query

  alias Tuist.OnceEvents.TestReportIngestor
  alias Tuist.OnceEvents.TestReportPublication
  alias Tuist.Repo
  alias Tuist.Tests

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"phase" => "recover"}}), do: TestReportIngestor.recover_recent()

  def perform(%Oban.Job{args: %{"run_id" => id, "phase" => "followups"}}) do
    case Repo.get(TestReportPublication, id) do
      %TestReportPublication{state: "published", payload: payload} ->
        %{test: test, effects: effects} = :erlang.binary_to_term(payload, [:safe])

        {:ok, _} =
          Repo.transaction(fn ->
            publication = Repo.one!(from(p in TestReportPublication, where: p.id == ^id, lock: "FOR UPDATE"))

            if is_nil(publication.effects_dispatched_at) do
              Tests.finish_captured_effects(effects)

              publication
              |> Ecto.Changeset.change(effects_dispatched_at: DateTime.truncate(DateTime.utc_now(), :second))
              |> Repo.update!()
            end
          end)

        Tests.finish_test_publication(test)
        :ok

      _ ->
        {:error, :not_published}
    end
  end

  def perform(%Oban.Job{args: %{"run_id" => id}}) do
    case Repo.get(TestReportPublication, id) do
      nil ->
        :ok

      _publication ->
        case TestReportIngestor.publish_prepared(id) do
          {:ok, :in_progress} -> {:snooze, 5}
          {:ok, :yielded} -> {:snooze, 1}
          {:ok, _} -> :ok
          {:error, :publication_uncertain} -> {:discard, :publication_uncertain}
          {:error, :publication_preparation_failed} -> {:discard, :publication_preparation_failed}
          {:error, _} = error -> error
        end
    end
  end
end
