defmodule Tuist.Telemetry.QueryErrorContextTest do
  use ExUnit.Case, async: true

  alias Tuist.SentryEventFilter
  alias Tuist.Telemetry.QueryErrorContext

  @query_event [:tuist, :click_house_repo, :query]

  test "adds the failed query and timings to the matching event without parameter values" do
    error = %Ch.Error{code: 159, message: "Timeout exceeded"}
    query = "SELECT name FROM test_cases WHERE project_id = {project_id:Int64} AND name = {name:String}"

    :telemetry.execute(
      @query_event,
      %{
        query_time: System.convert_time_unit(15_000, :millisecond, :native),
        queue_time: System.convert_time_unit(25, :millisecond, :native),
        total_time: System.convert_time_unit(15_025, :millisecond, :native)
      },
      %{
        repo: Tuist.ClickHouseRepo,
        result: {:error, error},
        query: query,
        params: %{project_id: 123, name: "private customer value"},
        cast_params: %{name: "another private value"}
      }
    )

    original = event(error, %{existing_context: "preserved"})
    enriched = SentryEventFilter.before_send(original)

    assert enriched.original_exception == error
    assert enriched.extra.existing_context == "preserved"

    assert enriched.extra.database_query == %{
             repository: "Tuist.ClickHouseRepo",
             statement: query,
             statement_truncated: false,
             parameters: "[REDACTED]",
             timings_ms: %{query_time: 15_000.0, queue_time: 25.0, total_time: 15_025.0}
           }

    refute inspect(enriched.extra) =~ "private customer value"
    refute inspect(enriched.extra) =~ "another private value"
  end

  test "does not attach a recovered query to a later error" do
    error = %Ch.Error{code: 241, message: "Memory limit exceeded"}
    emit_failure(error)
    :telemetry.execute(@query_event, %{}, %{result: {:ok, %Ch.Result{}}})

    original = event(error)
    assert SentryEventFilter.before_send(original) == original
  end

  test "does not attach a previous query to an unrelated exception" do
    emit_failure(%Ch.Error{code: 159, message: "Timeout exceeded"})
    original = event(%RuntimeError{message: "another failure"})

    assert SentryEventFilter.before_send(original) == original
  end

  test "retains only the latest failed query" do
    error = %Ch.Error{code: 159, message: "Timeout exceeded"}
    emit_failure(error, "SELECT 1")
    emit_failure(error, "SELECT 2")

    assert SentryEventFilter.before_send(event(error)).extra.database_query.statement == "SELECT 2"
  end

  test "captures pool failures and does not share context between tasks" do
    error = DBConnection.ConnectionError.exception("connection not available", :queue_timeout)
    emit_failure(error)
    original = event(error)

    assert %{database_query: %{statement: "SELECT 1"}} = SentryEventFilter.before_send(original).extra

    assert fn -> SentryEventFilter.before_send(original) end |> Task.async() |> Task.await() == original
  end

  test "bounds long statements without splitting Unicode characters" do
    error = %Ch.Error{code: 159, message: "Timeout exceeded"}
    emit_failure(error, "SELECT '" <> String.duplicate("é", 20_000) <> "'")

    context = SentryEventFilter.before_send(event(error)).extra.database_query
    assert context.statement_truncated
    assert String.length(context.statement) == 16_384
    assert String.valid?(context.statement)
  end

  test "supports the operations read repository" do
    error = %Ch.Error{code: 159, message: "Timeout exceeded"}

    :telemetry.execute([:tuist, :ops_click_house_repo, :query], %{}, %{
      repo: Tuist.OpsClickHouseRepo,
      result: {:error, error},
      query: "SELECT 1"
    })

    assert SentryEventFilter.before_send(event(error)).extra.database_query.repository == "Tuist.OpsClickHouseRepo"
  end

  test "ignores events without an original exception" do
    emit_failure(%Ch.Error{code: 159, message: "Timeout exceeded"})
    original = event(nil)
    assert QueryErrorContext.enrich_event(original) == original
  end

  defp emit_failure(error, query \\ "SELECT 1") do
    :telemetry.execute(@query_event, %{}, %{repo: Tuist.ClickHouseRepo, result: {:error, error}, query: query})
  end

  defp event(exception, extra \\ %{}) do
    %Sentry.Event{
      event_id: String.duplicate("a", 32),
      timestamp: "2026-09-09T00:00:00Z",
      original_exception: exception,
      extra: extra
    }
  end
end
