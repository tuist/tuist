defmodule Atlas.GTM.Outreach.ScannerTest do
  use Atlas.DataCase, async: true

  alias Atlas.GTM.Outreach.Scanner
  alias Atlas.GTM.SignalQuery

  test "skips recently-run queries by default" do
    now = ~U[2026-06-05 12:00:00Z]

    query = %SignalQuery{
      name: "Recent query",
      source: "brave",
      query: ~s("developer productivity"),
      result_limit: 5,
      last_run_at: DateTime.add(now, -60, :second)
    }

    assert %{queries: 0, skipped: 1, signals: 0, errors: []} =
             Scanner.run_query(query, now: now, query_cooldown_seconds: 3_600)
  end

  test "marks unsupported forced queries as run and reports the error" do
    now = ~U[2026-06-05 12:00:00Z]

    query =
      Repo.insert!(%SignalQuery{
        name: "Unsupported query",
        source: "rss",
        query: "iOS CI",
        result_limit: 5,
        enabled: true
      })

    assert %{
             queries: 1,
             skipped: 0,
             signals: 0,
             errors: [
               %{
                 query: "Unsupported query",
                 source: "rss",
                 reason: ~s({:unsupported_signal_source, "rss"})
               }
             ]
           } = Scanner.run_query(query, now: now, force?: true)

    assert Repo.get!(SignalQuery, query.id).last_run_at == now
  end
end
