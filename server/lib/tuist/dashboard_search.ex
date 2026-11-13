defmodule Tuist.DashboardSearch do
  @moduledoc """
  Searches already-authorized projects (accounts must be preloaded).

  `search/3` returns `%{results: [...], unavailable: [type],
  metadata: %{window_days: 30, per_type_limit: 5}}`.
  Invalid syntax adds `error: message` and returns no results or unavailable types.
  Filters and literal, case-insensitive text terms are ANDed before database limits.
  Run-specific filters enable run discovery; otherwise runs match exact IDs only.
  Empty searches suggest projects in caller order, with the preferred project first.
  Results preserve global relevance order with at most five results per type.

  All runs and native Once case attempts are restricted to the last 30 days.
  Shared case catalogs cannot honor run metadata filters and are excluded for them.
  Unsupported filters exclude a provider, rather than widening its scope.

  Every provider query is bounded:

  - Exact run IDs use a typed `id IN` predicate, so the primary key or the `idx_id`
    bloom filter prunes to the matching granules.
  - Shared test case names are found through the `idx_search_ngram` index on the
    lowercased module, suite and name. A selective term reads a few granules and
    returns complete results. A term that appears in most granules, such as
    "test", stops after 1,000,000 rows and returns the best matches among them,
    rather than failing.
  """

  alias Tuist.ClickHouseRepo
  alias Tuist.DashboardSearchQuery
  alias Tuist.Repo

  @metadata_keys ~w(branch commit status date pr)
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  # Must match the `idx_search_ngram` expression on `test_cases` exactly for the
  # index to apply.
  @test_case_search_text "lowerUTF8(concat(module_name, ' ', suite_name, ' ', name))"
  # Test cases are read without FINAL: every column they match on is part of the
  # sort key, so all versions of a case match alike, and `LIMIT 1 BY` keeps the
  # newest. FINAL would also disable the skip index that bounds the read.
  @sources [
    {"test_case", "test_cases", "id", "name", ["module_name", "suite_name", "name"], "last_ran_at", "tests/test-cases",
     nil},
    {"test_run", "test_run_summaries", "id", "scheme", ["scheme"], "ran_at", "tests/test-runs", nil},
    {"build", "build_runs FINAL", "id", "scheme", ["scheme", "configuration"], "inserted_at", "builds/build-runs",
     :xcode},
    {"build", "gradle_builds", "id", "root_project_name",
     ["root_project_name", "arrayStringConcat(requested_tasks, ' ')"], "inserted_at", "builds/build-runs", :gradle},
    {"build", "bazel_invocations FINAL", "invocation_id", "command",
     ["command", "arrayStringConcat(target_patterns, ' ')"], "inserted_at", "builds/invocations", :bazel},
    {"build", "cargo_builds", "id", "command", ["command"], "inserted_at", "builds/cargo-builds", :cargo},
    {"build", "mix_builds", "id", "mix_env", ["mix_env"], "inserted_at", "builds/mix-builds", :mix}
  ]

  def search(projects, raw_query, opts \\ []) do
    initial = %{results: [], unavailable: [], metadata: %{window_days: 30, per_type_limit: 5}}

    case DashboardSearchQuery.parse(raw_query) do
      {:error, message} -> Map.put(initial, :error, message)
      {:ok, query} -> search_query(projects, query, opts, initial)
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp search_query(projects, query, opts, initial) do
    preferred = Keyword.get(opts, :preferred_project_id)
    scope = query.filters["project"] || Keyword.get(opts, :project)
    projects = Enum.filter(projects, &(is_nil(scope) or String.downcase(&1.name) == String.downcase(scope)))
    {projects, terms} = normalize(projects, query.terms)

    query = %{query | terms: terms}
    project_map = Map.new(projects, &{&1.id, &1})

    cond do
      projects == [] or query.filters["is"] == "page" ->
        initial

      terms == [] and map_size(query.filters) == 0 ->
        %{
          initial
          | results:
              projects
              |> Enum.sort_by(&(&1.id != preferred))
              |> Enum.take(5)
              |> Enum.map(&result("project", &1.name, String.capitalize(to_string(&1.build_system)), base(&1), &1.name))
        }

      true ->
        project_rows =
          if eligible?(query, "project", false, false) do
            projects
            |> Enum.filter(fn p ->
              Enum.all?(terms, &(String.contains?(String.downcase(base(p)), &1) or to_string(p.id) == &1))
            end)
            |> Enum.map(fn p ->
              {rank(p.name, to_string(p.id), terms), p.id, 0,
               result("project", p.name, String.capitalize(to_string(p.build_system)), base(p), p.name)}
            end)
          else
            []
          end

        deadline = Keyword.get(opts, :deadline, System.monotonic_time(:millisecond) + 2_000)

        {rows, unavailable} =
          Enum.reduce(providers(projects, query, preferred), {project_rows, []}, fn {type, load}, {rows, errors} ->
            # Never start another provider after the budget expires. An in-flight
            # query still has its own server/driver timeout and retains admission.
            outcome =
              if System.monotonic_time(:millisecond) < deadline,
                do: safely(load),
                else: {:error, :unavailable}

            case outcome do
              {:ok, matches} -> {rows ++ Enum.map(matches, &decorate(&1, project_map)), errors}
              {:error, :unavailable} -> {rows, errors ++ [type]}
            end
          end)

        %{initial | results: rank_results(rows, preferred), unavailable: Enum.uniq(unavailable)}
    end
  end

  defp eligible?(query, type, metadata?, pr?) do
    (is_nil(query.filters["is"]) or query.filters["is"] == type) and
      (metadata? or not metadata_filter?(query)) and
      (pr? or not Map.has_key?(query.filters, "pr"))
  end

  defp metadata_filter?(query), do: Enum.any?(@metadata_keys, &Map.has_key?(query.filters, &1))

  defp exact_only?(query, type),
    do: type in ["build", "test_run"] and is_nil(query.filters["is"]) and not metadata_filter?(query)

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp providers(projects, query, preferred) do
    broad? = Enum.any?(query.terms, &(String.length(&1) >= 3)) or map_size(query.filters) > 0
    uuid? = Enum.any?(query.terms, &uuid?/1)

    ch =
      Enum.flat_map(@sources, fn {type, _, _, _, _, _, _, system} = source ->
        ids = for p <- projects, is_nil(system) or p.build_system == system, do: p.id

        # Bazel invocation IDs may be arbitrary strings. Other run IDs are UUIDs,
        # so ordinary words cannot match their exact-identity-only searches.
        identity? = system == :bazel or uuid?
        useful? = not exact_only?(query, type) or identity?

        if broad? and useful? and ids != [] and
             eligible?(query, type, type != "test_case", type != "test_case" and system != :bazel),
           do: [{type, fn -> clickhouse(source, ids, query, preferred) end}],
           else: []
      end)

    pg =
      Enum.flat_map([:preview, :once_build, :once_test, :once_case], fn kind ->
        type =
          case kind do
            :preview -> "preview"
            :once_build -> "build"
            :once_test -> "test_run"
            :once_case -> "test_case"
          end

        ids = for p <- projects, kind == :preview or p.build_system == :once, do: p.id

        supported =
          broad? and
            (not exact_only?(query, type) or uuid?) and
            eligible?(query, type, kind != :once_case, kind == :preview) and
            not (kind == :preview and Map.has_key?(query.filters, "status"))

        if ids != [] and supported, do: [{type, fn -> postgres(kind, ids, query, preferred) end}], else: []
      end)

    ch ++ pg
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp clickhouse({type, table, id, title, fields, timestamp, route, system}, ids, query, preferred) do
    catalog? = type == "test_case"
    status = if catalog?, do: "''", else: ch_status()

    pr =
      cond do
        catalog? or system == :bazel -> "0"
        type == "test_run" -> "if(pull_request_number > 0, toUInt64(pull_request_number), #{ch_pr()})"
        true -> ch_pr()
      end

    branch = if catalog?, do: "''", else: "git_branch"
    commit = if catalog?, do: "''", else: "git_commit_sha"
    fields = if catalog?, do: fields, else: fields ++ [branch, commit]
    text = Enum.map_join(fields, ", ' ', ", &"ifNull(#{&1}, '')")

    context =
      if catalog?,
        do:
          "arrayStringConcat(arrayDistinct(arrayFilter(x -> x != '', [ifNull(module_name, ''), ifNull(suite_name, '')])), ' · ')",
        else: "''"

    window = if catalog?, do: "", else: "AND #{timestamp} >= now64(6) - INTERVAL 30 DAY AND #{timestamp} <= now64(6)"
    native = if system == :cargo, do: "AND command != 'nextest'", else: ""
    filters = predicates(query, :ch, %{branch: branch, commit: commit, status: status, date: timestamp, pr: pr})

    match =
      "arrayAll(t -> positionCaseInsensitiveUTF8(concat(#{text}), t) > 0 OR lowerUTF8(toString(#{id})) = t, {terms:Array(String)})"

    match =
      cond do
        catalog? and query.terms != [] -> test_case_prefilter(query.terms) <> " AND " <> match
        not exact_only?(query, type) -> match
        # Bazel invocation IDs are strings in the sort key; other run IDs are UUIDs.
        system == :bazel -> match <> " AND has({terms:Array(String)}, lowerUTF8(toString(#{id})))"
        true -> match <> " AND #{id} IN {uuids:Array(UUID)}"
      end

    score =
      "multiIf(lowerUTF8(toString(#{id})) = {term:String} OR lowerUTF8(#{title}) = {term:String}, 0, startsWith(lowerUTF8(#{title}), {term:String}), 1, 2)"

    order = "ORDER BY #{score}, project_id = {preferred:Int64} DESC, #{timestamp} DESC, #{id}"
    condition = "project_id IN {ids:Array(Int64)} #{window} #{native} AND (#{match}) #{filters}"

    select = fn condition ->
      """
      SELECT toString(#{id}), project_id, #{title}, #{score},
        -toUnixTimestamp(#{timestamp}), #{status}, #{branch}, #{commit}, formatDateTime(#{timestamp}, '%Y-%m-%dT%H:%i:%SZ', 'UTC'), toString(#{pr}), #{context}
      FROM #{table}
      WHERE #{condition}
      #{order}
      LIMIT 1 BY project_id, #{id}
      LIMIT 5
      """
    end

    params =
      query.terms
      |> Enum.with_index()
      |> Enum.reduce(ch_params(ids, query, preferred), fn {term, index}, params ->
        params
        |> Map.put("pattern_#{index}", like_superset(term))
        |> then(&if(uuid?(term), do: Map.put(&1, "uuid_#{index}", term), else: &1))
      end)

    # A broad case name can match a million rows. Sorting them with their display
    # columns exceeds the memory limit, so one query picks the five case IDs and a
    # second formats them. They are separate queries because ClickHouse counts a
    # subquery's reads against the outer query's limits: the pick could exhaust
    # them and cut off the formatting read. The pick returns the best matches among
    # the rows it read; the formatting read is bounded by five IDs and stays exact.
    result =
      if catalog? do
        pick = "SELECT toString(id) FROM test_cases WHERE #{condition} #{order} LIMIT 1 BY project_id, id LIMIT 5"

        with {:ok, %{rows: [_ | _] = picked}} <- ch_query(pick, params, "break") do
          ch_query(
            select.("project_id IN {ids:Array(Int64)} AND id IN {case_ids:Array(UUID)}"),
            Map.put(params, "case_ids", List.flatten(picked)),
            "throw"
          )
        end
      else
        ch_query(select.(condition), params, "throw")
      end

    case result do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &{type, route, &1})}
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp ch_query(sql, params, read_overflow_mode) do
    ClickHouseRepo.query(sql, params,
      settings: [
        max_execution_time: 2,
        max_rows_to_read: 1_000_000,
        max_bytes_to_read: 100_000_000,
        read_overflow_mode: read_overflow_mode,
        max_memory_usage: 200_000_000,
        max_threads: 2,
        do_not_merge_across_partitions_select_final: 0,
        optimize_move_to_prewhere_if_final: 0,
        use_skip_indexes_if_final: 0
      ],
      timeout: 3_000
    )
  end

  # One indexable condition per term. The exact `positionCaseInsensitiveUTF8`
  # check still decides the result, so this only needs to match a superset:
  # `%` and `_` in a term stay wildcards, and backslashes become `_`. Sigma becomes
  # `_` too: `lowerUTF8` turns a word-final Σ into ς, which Elixir lowercases to σ.
  defp test_case_prefilter(terms) do
    terms
    |> Enum.with_index()
    |> Enum.map_join(" AND ", fn {term, index} ->
      like = "#{@test_case_search_text} LIKE {pattern_#{index}:String}"
      if uuid?(term), do: "(#{like} OR id = {uuid_#{index}:UUID})", else: like
    end)
  end

  defp like_superset(term), do: "%" <> String.replace(term, ["\\", "σ", "ς"], "_") <> "%"

  defp uuid?(term), do: Regex.match?(@uuid, term)

  defp ch_status do
    "multiIf(toString(status) IN ('failure', 'failed_processing'), 'failed', toString(status) = 'success', 'passed', toString(status) IN ('processing', 'in_progress'), 'running', '')"
  end

  defp ch_pr, do: "toUInt64OrZero(extract(git_ref, '^refs/(?:pull|merge-requests)/([0-9]{1,10})/(?:head|merge)$'))"

  defp pg_pr,
    do: "coalesce(substring(git_ref from '^refs/(?:pull|merge-requests)/([0-9]{1,10})/(?:head|merge)$'), '0')::bigint"

  defp postgres(kind, ids, query, preferred) do
    c = pg_source(kind)
    text = Enum.map_join(c.fields, ", ' ', ", &"coalesce(#{&1}, '')")
    filters = predicates(query, :pg, %{branch: c.branch, commit: c.commit, status: c.status, date: c.timestamp, pr: c.pr})

    match =
      "NOT EXISTS (SELECT 1 FROM unnest($2::text[]) AS term WHERE strpos(lower(concat(#{text})), term) = 0 AND lower(#{c.id}) != term)"

    match = if exact_only?(query, c.type), do: match <> " AND lower(#{c.id}) = ANY($2::text[])", else: match

    sql = """
    SELECT #{c.id}, #{c.project}, coalesce(#{c.title}, ''),
      CASE WHEN lower(#{c.id}) = $4 OR lower(#{c.title}) = $4 THEN 0 WHEN starts_with(lower(#{c.title}), $4) THEN 1 ELSE 2 END,
      -extract(epoch from #{c.timestamp})::bigint, #{c.status}, #{c.branch}, #{c.commit}, #{c.timestamp}::text, (#{c.pr})::text, #{c.context}, #{c.route}
    FROM #{c.table}
    WHERE #{c.project} = ANY($1) #{c.window} AND (#{match}) #{filters}
    ORDER BY 4, (#{c.project} = $3) DESC, #{c.timestamp} DESC, #{c.id}
    LIMIT 5
    """

    case postgres_query(sql, pg_params(ids, query, preferred)) do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(rows, fn row ->
           route =
             if kind == :once_case,
               do: "once/test-runs/#{URI.encode(List.last(row), &URI.char_unreserved?/1)}/test-cases",
               else: List.last(row)

           {c.type, route, Enum.drop(row, -1)}
         end)}

      {:error, _} ->
        {:error, :unavailable}
    end
  end

  defp pg_source(:preview) do
    %{
      type: "preview",
      table: "previews",
      id: "id::text",
      project: "project_id",
      title: "display_name",
      fields: ["display_name", "release_notes", "git_branch", "git_commit_sha"],
      context: "concat_ws(' · ', nullif(version, ''), nullif(track, ''))",
      timestamp: "inserted_at",
      branch: "git_branch",
      commit: "git_commit_sha",
      status: "''",
      pr: pg_pr(),
      route: "'previews'",
      window: ""
    }
  end

  defp pg_source(:once_case) do
    %{
      type: "test_case",
      table: "once_test_case_runs c JOIN once_runs r ON r.id = c.once_run_id AND r.project_id = c.project_id",
      id: "c.id::text",
      project: "c.project_id",
      title: "c.name",
      fields: ["c.name", "c.class_name", "c.module", "c.case_id"],
      context: "concat_ws(' · ', nullif(c.module, ''), nullif(c.class_name, ''))",
      timestamp: "c.inserted_at",
      branch: "''",
      commit: "''",
      status: "''",
      pr: "0",
      route: "r.run_id",
      window: "AND r.inserted_at >= statement_timestamp() - interval '30 days' AND r.inserted_at <= statement_timestamp()"
    }
  end

  defp pg_source(kind) do
    test? = kind == :once_test

    %{
      type: if(test?, do: "test_run", else: "build"),
      table: "once_runs",
      id: "run_id",
      project: "project_id",
      title: "command_display",
      fields: ["command_display", "git_branch", "git_rev"],
      context: "''",
      timestamp: "inserted_at",
      branch: "git_branch",
      commit: "git_rev",
      status:
        "CASE WHEN finalization IN ('active','finalizing','finalization_pending') THEN 'running' WHEN finalization = 'finalized' AND exit_status = 0 THEN 'passed' WHEN finalization = 'finalized' AND exit_status != 0 THEN 'failed' ELSE '' END",
      pr: "0",
      route: if(test?, do: "'once/test-runs'", else: "'once/runs'"),
      window:
        "AND inserted_at >= statement_timestamp() - interval '30 days' AND inserted_at <= statement_timestamp() AND #{if test?, do: "kind = 'test'", else: "kind != 'test'"}"
    }
  end

  defp predicates(query, dialect, columns) do
    Enum.map_join(query.filters, " ", fn
      {"branch", _} ->
        "AND lower(#{columns.branch}) = #{param(dialect, :branch)}"

      {"commit", _} ->
        function = if dialect == :ch, do: "startsWith", else: "starts_with"
        "AND #{function}(lower(#{columns.commit}), #{param(dialect, :commit)})"

      {"status", _} ->
        "AND (#{columns.status}) = #{param(dialect, :status)}"

      {"pr", _} ->
        "AND (#{columns.pr}) = #{param(dialect, :pr)}"

      {"date", {first, last}} ->
        from = if first, do: "AND #{columns.date} >= #{param(dialect, :from)}", else: ""
        to = if last, do: "AND #{columns.date} < #{param(dialect, :to)}", else: ""
        from <> " " <> to

      _ ->
        ""
    end)
  end

  defp param(:ch, key) do
    case key do
      :from -> "parseDateTime64BestEffort({from:String}, 6, 'UTC')"
      :to -> "parseDateTime64BestEffort({to:String}, 6, 'UTC')"
      :pr -> "{pr:UInt64}"
      key -> "{#{key}:String}"
    end
  end

  defp param(:pg, key),
    do:
      %{
        branch: "$5",
        commit: "$6",
        status: "$7",
        from: "$8::text::timestamptz",
        to: "$9::text::timestamptz",
        pr: "$10::bigint"
      }[key]

  defp ch_params(ids, query, preferred) do
    {first, last} = Map.get(query.filters, "date", {nil, nil})

    %{
      ids: ids,
      terms: query.terms,
      preferred: preferred || -1,
      term: Enum.join(query.terms, " "),
      branch: query.filters["branch"] || "",
      commit: query.filters["commit"] || "",
      status: query.filters["status"] || "",
      from: first || "",
      to: last || "",
      pr: query.filters["pr"] || 0,
      uuids: Enum.filter(query.terms, &uuid?/1)
    }
  end

  defp pg_params(ids, query, preferred) do
    p = ch_params(ids, query, preferred)
    [p.ids, p.terms, p.preferred, p.term, p.branch, p.commit, p.status, p.from, p.to, p.pr]
  end

  defp postgres_query(sql, params) do
    # Cast unused optional parameters too: PostgreSQL otherwise cannot infer
    # their types when only some filters are present.
    sql = "WITH search_parameters AS (SELECT $5::text, $6::text, $7::text, $8::text, $9::text, $10::bigint) " <> sql

    case Repo.transaction(fn ->
           Repo.query!("SET LOCAL statement_timeout = '2s'")
           Repo.query(sql, params, timeout: 3_000)
         end) do
      {:ok, result} -> result
      {:error, _} -> {:error, :unavailable}
    end
  end

  defp decorate(
         {type, route, [id, project_id, title, score, recency, status, branch, commit, timestamp, pr, context]},
         projects
       ) do
    project = Map.fetch!(projects, project_id)

    details =
      if type in ["build", "test_run", "preview"],
        do: [context, if(pr not in [nil, "0", ""], do: "PR ##{pr}"), status, branch, timestamp, commit],
        else: [context]

    subtitle = details |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" · ")
    path = base(project) <> "/" <> route <> "/" <> URI.encode(id, &URI.char_unreserved?/1)
    {score, project_id, recency, result(type, if(title in [nil, ""], do: id, else: title), subtitle, path, project.name)}
  end

  defp rank_results(rows, preferred) do
    rows
    |> Enum.sort_by(fn {score, project_id, recency, item} ->
      {score, project_id != preferred, recency, item.title, item.path}
    end)
    |> Enum.uniq_by(fn {_, _, _, item} -> item.path end)
    |> Enum.map(&elem(&1, 3))
    |> Enum.map_reduce(%{}, fn item, counts ->
      count = Map.get(counts, item.type, 0)
      {if(count < 5, do: item), Map.put(counts, item.type, count + 1)}
    end)
    |> elem(0)
    |> Enum.reject(&is_nil/1)
  end

  defp safely(load) do
    load.()
  rescue
    _ -> {:error, :unavailable}
  end

  defp result(type, title, subtitle, path, project),
    do: %{type: type, title: title, subtitle: subtitle, path: path, project: project}

  defp base(project), do: "/#{project.account.name}/#{project.name}"

  defp rank(title, id, terms) do
    term = Enum.join(terms, " ")

    cond do
      String.downcase(title) == term or id == term -> 0
      String.starts_with?(String.downcase(title), term) -> 1
      true -> 2
    end
  end

  defp normalize(projects, [query]) do
    path = if String.starts_with?(query, ["https://", "http://"]), do: URI.parse(query).path || "", else: query

    if String.starts_with?(path, "/") do
      path = path |> String.split(["?", "#"], parts: 2) |> hd() |> String.trim_trailing("/")

      scoped =
        Enum.filter(
          projects,
          &(String.downcase(path) == String.downcase(base(&1)) or
              String.starts_with?(String.downcase(path), String.downcase(base(&1)) <> "/"))
        )

      term =
        if Enum.any?(scoped, &(String.downcase(path) == String.downcase(base(&1)))),
          do: path,
          else: path |> String.split("/") |> List.last() |> URI.decode()

      {scoped, [String.downcase(term)]}
    else
      {projects, [query]}
    end
  end

  defp normalize(projects, terms) do
    Enum.reduce(terms, {projects, []}, fn term, {scoped, normalized} ->
      {scoped, [term]} = normalize(scoped, [term])
      {scoped, normalized ++ [term]}
    end)
  end
end
