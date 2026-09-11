defmodule Tuist.ClickHouseRepoTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.SentryEventFilter

  test "a failed raw query enriches the original error event" do
    with_read_repo(fn ->
      statement = "SELECT throwIf(1) WHERE {name:String} = {name:String}"

      error = assert_raise Ch.Error, fn -> ClickHouseRepo.query!(statement, %{name: "private value"}) end

      event = error_event(error)
      assert event.original_exception == error
      assert event.extra.database_query.statement == statement
      assert event.extra.database_query.timings_ms.total_time > 0
      refute inspect(event.extra) =~ "private value"
    end)
  end

  test "a failed generated query enriches the original error event" do
    with_read_repo(fn ->
      value = "private value"
      query = from(n in fragment("numbers(1)"), where: ^value == ^value, select: fragment("throwIf(1)"))
      {statement, _params} = ClickHouseRepo.to_sql(:all, query)

      error = assert_raise Ch.Error, fn -> ClickHouseRepo.all(query) end

      event = error_event(error)
      assert event.extra.database_query.statement == statement
      refute inspect(event.extra) =~ "private value"
    end)
  end

  test "query settings override the connection defaults" do
    with_read_repo(fn ->
      assert resource_settings() == %{
               max_memory_usage: 6 * 1024 * 1024 * 1024,
               max_threads: 4
             }

      assert resource_settings(
               settings: [
                 max_threads: 2,
                 max_memory_usage: 1024 * 1024 * 1024
               ]
             ) == %{
               max_memory_usage: 1024 * 1024 * 1024,
               max_threads: 2
             }
    end)
  end

  defp resource_settings(options \\ []) do
    %{rows: [[max_threads, max_memory_usage]]} =
      ClickHouseRepo.query!(
        """
        SELECT
          getSetting('max_threads'),
          getSetting('max_memory_usage')
        """,
        %{},
        options
      )

    %{max_threads: max_threads, max_memory_usage: max_memory_usage}
  end

  defp error_event(error) do
    original = Sentry.Event.create_event(exception: error)
    enriched = SentryEventFilter.before_send(original)
    assert enriched.exception == original.exception
    assert enriched.fingerprint == original.fingerprint
    enriched
  end

  defp with_read_repo(fun) do
    previous_dynamic_repo = ClickHouseRepo.get_dynamic_repo()

    try do
      ClickHouseRepo.put_dynamic_repo(ClickHouseRepo)
      fun.()
    after
      ClickHouseRepo.put_dynamic_repo(previous_dynamic_repo)
    end
  end
end
