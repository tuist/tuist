defmodule Mix.Tasks.Pulse.Parity do
  @shortdoc "Compares query answers between a reference backend and Pulse"

  @moduledoc """
  Runs the queries of Grafana dashboards, alert rule exports or a plain query
  list against a reference backend and a candidate (Pulse), over several
  windows, and reports where their answers differ (`Pulse.Parity`).

      mix pulse.parity QUERIES.json... \\
        --reference-prometheus URL --reference-loki URL \\
        --candidate-prometheus URL --candidate-loki URL

  Options:

    * `--window` — comma-separated windows, default `1h,6h,24h,7d`.
    * `--lag` — seconds to leave out at the end of every window so both
      backends have the same data, default 300.
    * `--var name=value` — a dashboard variable; unset ones match anything.
    * `--datasource uid=prometheus|loki` — the language of a datasource UID
      that queries reference without a type.
    * `--tolerance` — relative tolerance for values, default 1e-9.
    * `--report PATH` — write every result as JSON.

  Request headers (credentials, `X-Scope-OrgID`) come from the
  `PULSE_PARITY_REFERENCE_HEADERS` and `PULSE_PARITY_CANDIDATE_HEADERS`
  environment variables, one `Name: value` per line, so secrets stay out of
  shell history. The task exits non-zero when any answer differs or fails.
  """

  use Mix.Task

  @switches [
    reference_prometheus: :string,
    reference_loki: :string,
    candidate_prometheus: :string,
    candidate_loki: :string,
    window: :string,
    lag: :integer,
    var: :keep,
    datasource: :keep,
    tolerance: :float,
    report: :string
  ]

  @impl true
  def run(argv) do
    {opts, files, invalid} = OptionParser.parse(argv, strict: @switches)

    if invalid != [] or files == [],
      do: Mix.raise("usage: mix pulse.parity QUERIES.json... (see mix help pulse.parity)")

    {:ok, _} = Application.ensure_all_started(:req)

    datasources = pairs(opts, :datasource)

    queries =
      Enum.flat_map(files, &(&1 |> File.read!() |> Pulse.JSON.decode!() |> Pulse.Parity.extract(&1, datasources)))

    queries = Enum.uniq_by(queries, &{&1.expr, &1.kind})
    endpoints = endpoints(opts, queries)
    windows = opts |> Keyword.get(:window, "1h,6h,24h,7d") |> String.split(",") |> Enum.map(&seconds/1)

    run_opts = [
      now: System.os_time(:second),
      lag: Keyword.get(opts, :lag, 300),
      vars: pairs(opts, :var),
      tolerance: Keyword.get(opts, :tolerance, 1.0e-9)
    ]

    Mix.shell().info("#{length(queries)} queries x #{length(windows)} windows")

    results =
      for query <- queries, window <- windows do
        result = Pulse.Parity.run(query, endpoints, window, run_opts)
        if result.outcome != :match, do: Mix.shell().info("#{label(result.outcome)} [#{window}s] #{query.source}")
        result
      end

    summary = Pulse.Parity.summary(results)
    Mix.shell().info("summary: #{inspect(summary)}")
    if path = opts[:report], do: File.write!(path, results |> Enum.map(&report/1) |> Pulse.JSON.encode!())
    if Map.keys(summary) -- [:match] != [], do: exit({:shutdown, 1})
  end

  defp endpoints(opts, queries) do
    languages = queries |> Enum.map(& &1.language) |> Enum.uniq()

    for side <- [:reference, :candidate], language <- languages, into: %{} do
      key = :"#{side}_#{if language == :promql, do: "prometheus", else: "loki"}"
      url = opts[key] || Mix.raise("--#{String.replace(to_string(key), "_", "-")} is required for #{language} queries")
      {{side, language}, {String.trim_trailing(url, "/"), headers(side)}}
    end
  end

  defp headers(side) do
    "PULSE_PARITY_#{side |> to_string() |> String.upcase()}_HEADERS"
    |> System.get_env("")
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [name, value] = String.split(line, ":", parts: 2)
      {String.trim(name), String.trim(value)}
    end)
  end

  defp pairs(opts, key) do
    for value <- Keyword.get_values(opts, key), into: %{} do
      [name, setting] = String.split(value, "=", parts: 2)
      {name, setting}
    end
  end

  defp seconds(text) do
    case Integer.parse(text) do
      {n, "s"} -> n
      {n, "m"} -> n * 60
      {n, "h"} -> n * 3600
      {n, "d"} -> n * 86_400
      _ -> Mix.raise("invalid window #{inspect(text)}")
    end
  end

  defp label({name, _}), do: name

  defp report(result) do
    {outcome, details} =
      case result.outcome do
        :match -> {:match, nil}
        {name, details} -> {name, inspect(details, limit: 50, printable_limit: 500)}
      end

    %{
      source: result.source,
      language: result.language,
      window: result.window,
      expr: result.expr,
      outcome: outcome,
      details: details
    }
  end
end
