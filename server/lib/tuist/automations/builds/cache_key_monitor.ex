defmodule Tuist.Automations.Builds.CacheKeyMonitor do
  @moduledoc "Detects same-commit cache-key divergence from reported build-unit identities."

  alias Tuist.ClickHouseRepo
  alias Tuist.Repo

  @page_size 1000

  def sources(:gradle), do: ["gradle"]
  def sources(:bazel), do: ["bazel"]
  def sources(:once), do: ["once"]
  def sources(:xcode), do: ["xcode_module", "xcode_compilation"]
  def sources(_), do: []

  def page_size, do: @page_size

  def page(project_id, source, cursor, cutoff, opts \\ [])

  def page(project_id, "once", cursor, cutoff, opts) do
    params = [
      project_id,
      cutoff,
      cursor,
      @page_size,
      Keyword.get(opts, :commit, ""),
      Keyword.get(opts, :until, DateTime.utc_now())
    ]

    %{rows: rows} = Repo.query!(once_query(), params, timeout: 20_000)
    Enum.map(rows, &finding("once", &1))
  end

  def page(project_id, source, cursor, cutoff, opts) do
    params = %{
      project_id: project_id,
      cutoff: cutoff,
      cursor: cursor,
      limit: @page_size,
      commit: Keyword.get(opts, :commit, ""),
      until: Keyword.get(opts, :until, DateTime.utc_now())
    }

    %{rows: rows} =
      ClickHouseRepo.query!(query(source), params,
        settings: [max_threads: 2, max_memory_usage: 536_870_912, max_execution_time: 15],
        timeout: 20_000
      )

    Enum.map(rows, &finding(source, &1))
  end

  def commits(project_id, source, cursor, cutoff, since, until) do
    %{rows: rows} =
      if source == "once" do
        Repo.query!(
          """
          SELECT git_rev FROM once_runs
          WHERE project_id = $1 AND inserted_at >= $2 AND inserted_at <= $3
            AND is_ci AND NOT git_dirty AND finalization = 'finalized' AND git_rev > $4
          GROUP BY git_rev HAVING count(DISTINCT id) > 1 AND max(inserted_at) >= $5
          ORDER BY git_rev LIMIT 11
          """,
          [project_id, cutoff, until, cursor, since],
          timeout: 20_000
        )
      else
        ClickHouseRepo.query!(
          commits_query(source),
          %{project_id: project_id, cutoff: cutoff, until: until, cursor: cursor, since: since},
          settings: [max_threads: 2, max_memory_usage: 536_870_912, max_execution_time: 15],
          timeout: 20_000
        )
      end

    Enum.map(rows, &hd/1)
  end

  def commits_query(source) do
    {table, id, commit, timestamp, extra} = parent(source)

    """
    SELECT #{commit} AS commit FROM #{table}
    WHERE project_id = {project_id:Int64} AND #{timestamp} >= {cutoff:DateTime64(6)}
      AND #{timestamp} <= {until:DateTime64(6)} AND is_ci AND #{commit} > {cursor:String} #{extra}
    GROUP BY commit HAVING uniqExact(#{id}) > 1 AND max(#{timestamp}) >= {since:DateTime64(6)}
    ORDER BY commit LIMIT 11
    """
  end

  defp parent("gradle"), do: {"gradle_builds", "id", "git_commit_sha", "inserted_at", ""}
  defp parent("bazel"), do: {"bazel_invocations FINAL", "invocation_id", "git_commit_sha", "inserted_at", ""}
  defp parent("xcode_module"), do: {"command_events", "id", "coalesce(git_commit_sha, '')", "created_at", ""}

  defp parent("xcode_compilation"),
    do: {"build_runs FINAL", "id", "git_commit_sha", "updated_at", "AND inserted_at >= {cutoff:DateTime64(6)}"}

  defp finding(source, [identity, name, commit, first_key, first_run, second_key, second_run]) do
    %{
      source: source,
      unit_key: identity,
      unit_name: name,
      commit_sha: commit,
      first_key: first_key,
      first_run: first_run,
      second_key: second_key,
      second_run: second_run
    }
  end

  # Collapse retries before comparison. A description/identity with multiple
  # keys in one run is ambiguous, not evidence of cross-build inconsistency.
  def query(source) do
    """
    SELECT identity, evidence.1, evidence.2, evidence.3, evidence.4, evidence.5, evidence.6
    FROM (
    SELECT identity, argMax(tuple(name, commit, first_key, first_run, second_key, second_run), tuple(seen, commit)) AS evidence
    FROM (
      SELECT identity, commit, any(name) AS name, max(seen) AS seen,
             min(key) AS first_key, argMin(run_id, key) AS first_run,
             max(key) AS second_key, argMax(run_id, key) AS second_run
      FROM (
        SELECT identity, commit, run_id, any(name) AS name,
               any(cache_key) AS key, max(seen) AS seen
        FROM (#{observations(source)})
        WHERE notEmpty(commit) AND notEmpty(cache_key) AND identity > {cursor:String}
        GROUP BY identity, commit, run_id
        HAVING min(cache_key) = max(cache_key)
      )
      GROUP BY identity, commit
      HAVING min(key) != max(key)
    )
    GROUP BY identity
    )
    ORDER BY identity
    LIMIT {limit:UInt32}
    """
  end

  defp parents(table, timestamp, upper, limit \\ 32) do
    """
    SELECT * FROM #{table} WHERE project_id = {project_id:Int64}
      AND #{timestamp} >= {cutoff:DateTime} AND #{upper} <= {until:DateTime64(6)}
      AND is_ci AND notEmpty(coalesce(git_commit_sha, ''))
      AND ({commit:String} = '' OR git_commit_sha = {commit:String})
      ORDER BY #{timestamp} DESC, id DESC LIMIT #{limit} BY git_commit_sha
    """
  end

  defp observations("gradle") do
    parents = parents("gradle_builds", "inserted_at", "inserted_at")

    """
    SELECT toJSONString(tuple(b.root_project_name, t.build_path, t.task_path, t.task_type)) AS identity,
           t.task_path AS name, b.git_commit_sha AS commit, toString(b.id) AS run_id,
           t.cache_key AS cache_key, t.inserted_at AS seen
    FROM gradle_tasks t
    INNER JOIN (#{parents}) b
      ON b.id = t.gradle_build_id AND b.project_id = t.project_id
    WHERE t.gradle_build_id IN (SELECT id FROM (#{parents}))
      AND t.project_id = {project_id:Int64} AND b.project_id = {project_id:Int64}
      AND t.inserted_at >= {cutoff:DateTime} AND b.inserted_at >= {cutoff:DateTime}
      AND b.is_ci AND notEmpty(b.root_project_name) AND notEmpty(t.build_path)
      AND notEmpty(t.task_path) AND notEmpty(t.task_type)
      AND (t.cacheability = 'cacheable' OR (t.cacheability = '' AND t.cacheable))
    """
  end

  defp observations("bazel") do
    parents = parents("bazel_invocations FINAL", "inserted_at", "inserted_at")

    """
    SELECT toJSONString(tuple(e.target_label, e.action_mnemonic, e.configuration_id, e.output_path)) AS identity,
           concat(e.target_label, ' ', e.action_mnemonic, ' ', e.output_path) AS name,
           b.git_commit_sha AS commit, b.invocation_id AS run_id, e.action_digest AS cache_key,
           e.inserted_at AS seen
    FROM reapi_cache_events e
    INNER JOIN (#{parents}) b
      ON b.invocation_id = e.invocation_id AND b.project_id = e.project_id
    WHERE e.project_id = {project_id:Int64} AND b.project_id = {project_id:Int64}
      AND e.inserted_at >= {cutoff:DateTime} AND b.inserted_at >= {cutoff:DateTime}
      AND b.is_ci AND e.operation = 'action_cache' AND e.client_kind = 'bazel'
      AND notEmpty(e.target_label) AND notEmpty(e.action_mnemonic) AND notEmpty(e.output_path)
    """
  end

  defp observations("xcode_module") do
    parents = parents("command_events", "created_at", "created_at", 128)

    """
    SELECT toJSONString(tuple(p.name, t.name, t.product, t.bundle_id, t.product_name,
           extract(coalesce(b.command_arguments, ''), '(?:--configuration|--config|-c)[ =]+([^ ]+)'),
           extract(coalesce(b.command_arguments, ''), '--profile[ =]+([^ ]+)'),
           arraySort(if(empty(t.hashed_destinations), t.destinations, t.hashed_destinations)))) AS identity,
           concat(p.name, '/', t.name) AS name, coalesce(b.git_commit_sha, '') AS commit,
           toString(b.id) AS run_id, coalesce(t.binary_cache_hash, '') AS cache_key,
           t.inserted_at AS seen
    FROM xcode_targets t
    INNER JOIN (#{parents}) b ON b.id = t.command_event_id
    INNER JOIN (SELECT * FROM xcode_projects WHERE xcode_graph_id IN (
      SELECT toUUIDOrNull(id) FROM xcode_graphs WHERE command_event_id IN (SELECT id FROM (#{parents})))) p
      ON p.id = toString(t.xcode_project_id) AND p.command_event_id = b.id
    WHERE t.command_event_id IN (SELECT id FROM (#{parents}))
      AND t.inserted_at IN (
        SELECT inserted_at FROM xcode_targets_by_project
        WHERE project_id = {project_id:Int64} AND inserted_at >= {cutoff:DateTime}
          AND inserted_at <= {until:DateTime64(6)} AND command_event_id IN (SELECT id FROM (#{parents}))
      )
      AND b.project_id = {project_id:Int64} AND (t.project_id = 0 OR t.project_id = {project_id:Int64})
      AND t.inserted_at >= {cutoff:DateTime} AND b.created_at >= {cutoff:DateTime}
      AND b.is_ci AND notEmpty(t.name) AND notEmpty(p.name)
    """
  end

  defp observations("xcode_compilation") do
    parents = parents("build_runs FINAL", "inserted_at", "updated_at")

    """
    SELECT toJSONString(tuple(t.type, t.description, b.configuration, b.scheme)) AS identity,
           coalesce(t.description, '') AS name, b.git_commit_sha AS commit,
           toString(b.id) AS run_id, t.key AS cache_key, t.inserted_at AS seen
    FROM cacheable_tasks t
    INNER JOIN (#{parents}) b ON b.id = t.build_run_id
    WHERE t.build_run_id IN (SELECT id FROM (#{parents}))
      AND b.project_id = {project_id:Int64} AND t.inserted_at >= {cutoff:DateTime}
      AND b.inserted_at >= {cutoff:DateTime} AND b.is_ci
      AND notEmpty(coalesce(t.description, ''))
    """
  end

  def once_query do
    """
    WITH observations AS (
      SELECT jsonb_build_array(a.target_execution_id, a.capability, a.action_index, a.identifier)::text AS identity,
             a.identifier AS name, b.git_rev AS commit, b.run_id AS run_id,
             a.cache_key AS cache_key, a.inserted_at AS seen
      FROM once_actions a
      JOIN (SELECT * FROM (SELECT r.*, row_number() OVER (PARTITION BY git_rev ORDER BY inserted_at DESC, id DESC) AS rank
        FROM once_runs r WHERE project_id = $1 AND inserted_at >= $2 AND inserted_at <= $6
          AND ($5 = '' OR git_rev = $5) AND is_ci AND NOT git_dirty AND finalization = 'finalized') ranked
        WHERE rank <= 32) b ON b.id = a.once_run_id AND b.project_id = a.project_id
      WHERE a.project_id = $1 AND b.project_id = $1 AND a.inserted_at >= $2
        AND b.inserted_at >= $2 AND b.inserted_at <= $6 AND ($5 = '' OR b.git_rev = $5)
        AND b.is_ci AND NOT b.git_dirty
        AND b.finalization = 'finalized' AND b.git_rev <> '' AND a.cache_key <> ''
        AND a.identifier <> '' AND a.target_execution_id <> '' AND a.capability <> ''
    ), per_run AS (
      SELECT identity, commit, run_id, min(name) AS name, min(cache_key) AS cache_key, max(seen) AS seen
      FROM observations WHERE identity > $3
      GROUP BY identity, commit, run_id HAVING min(cache_key) = max(cache_key)
    ), divergent AS (
      SELECT identity, min(name) AS name, commit, max(seen) AS seen,
             min(cache_key) AS first_key, (array_agg(run_id ORDER BY cache_key, run_id))[1] AS first_run,
             max(cache_key) AS second_key, (array_agg(run_id ORDER BY cache_key DESC, run_id))[1] AS second_run
      FROM per_run GROUP BY identity, commit
      HAVING min(cache_key) <> max(cache_key)
    )
    SELECT identity, name, commit, first_key, first_run, second_key, second_run
    FROM (SELECT DISTINCT ON (identity) * FROM divergent ORDER BY identity, seen DESC, commit) latest
    ORDER BY identity LIMIT $4
    """
  end
end
