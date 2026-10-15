defmodule Tuist.BuildEntities do
  @moduledoc """
  Stable, project-scoped build entities and their execution history.

  Entities are things a toolchain executes repeatedly across builds: Gradle
  tasks, Xcode generated-project modules and cache actions, Bazel cache
  actions, Once actions, and Mix files and modules. Each has a deterministic ID
  derived from its identity contract (`Tuist.BuildEntities.Identity`), and every
  execution is recorded as one slim observation in ClickHouse. Native fact
  tables stay the source of truth for execution details; observations link back
  to them through `parent_id` and `execution_id`.

  The seam is deliberately generic: `system` is an atom, `kind` a string, and
  public surfaces translate both into native vocabulary.

  Reads deduplicate observations by `id` before aggregating, so retried or
  replayed ingestion never biases counts or distributions.

  Every read runs under explicit ClickHouse limits and raises
  `Tuist.BuildEntities.QueryLimitError` when it exceeds its time or memory
  budget.
  """

  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.BuildEntities.Identity
  alias Tuist.BuildEntities.Observation
  alias Tuist.BuildEntities.QueryLimitError
  alias Tuist.ClickHouseRepo
  alias Tuist.OnceEvents.Run
  alias Tuist.Repo

  @statuses ~w(success failure skipped cancelled up_to_date no_source unknown)
  # `write` is a recorded cache write. It is neither a hit nor a miss, so it is
  # excluded from hit rates but kept in history and duration cohorts.
  @cache_statuses ~w(none hit hit_local hit_remote miss write)
  @hit_statuses ~w(hit hit_local hit_remote)
  @max_uint64 18_446_744_073_709_551_615
  @future_tolerance_seconds 60 * 60
  @past_tolerance_days 365
  @default_window_days 30
  @default_page_size 20
  @max_page_size 100

  # Reads scoped to one entity, or to the at most 100 entities of a page:
  # history, analytics, list counts and catalog lookups. Grouping by
  # `(entity_id, id)` follows the full sort key prefix, so in-order aggregation
  # finalizes one observation at a time rather than hashing the largest entity.
  # Spill thresholds sit well below the ceiling so grouping
  # and sorting go to disk before the query is killed.
  @entity_read_settings [
    max_threads: 2,
    max_memory_usage: 256 * 1024 * 1024,
    max_bytes_before_external_group_by: 64 * 1024 * 1024,
    max_bytes_before_external_sort: 64 * 1024 * 1024,
    optimize_aggregation_in_order: 1,
    aggregation_in_order_max_block_bytes: 1024 * 1024,
    max_block_size: 8192,
    max_streams_to_max_threads_ratio: 1,
    do_not_merge_across_partitions_select_final: 0,
    optimize_move_to_prewhere_if_final: 0,
    use_skip_indexes_if_final: 0,
    max_execution_time: 20
  ]

  # Reads over a whole project/system/kind range: the catalog listing and its
  # count, including the environment/branch membership filter.
  @kind_scan_settings [
    max_threads: 2,
    max_memory_usage: 512 * 1024 * 1024,
    max_bytes_before_external_group_by: 128 * 1024 * 1024,
    max_bytes_before_external_sort: 128 * 1024 * 1024,
    optimize_aggregation_in_order: 1,
    aggregation_in_order_max_block_bytes: 1024 * 1024,
    max_block_size: 8192,
    max_streams_to_max_threads_ratio: 1,
    do_not_merge_across_partitions_select_final: 0,
    optimize_move_to_prewhere_if_final: 0,
    use_skip_indexes_if_final: 0,
    max_execution_time: 30
  ]

  # TIMEOUT_EXCEEDED and MEMORY_LIMIT_EXCEEDED.
  @query_limit_codes [159, 241]

  # One page of history at most.
  @max_parent_lookups 100

  # The same cap as the other duration scatter charts.
  @max_scatter_observations 10_000

  @doc """
  Records observations. Each observation is a map with:

    * `:project_id`, `:system` (atom), `:kind` (string), `:identity` (string-keyed map)
    * `:parent_id` - build, invocation or run identifier (any string)
    * `:discriminator` - distinguishes repeated executions of one entity in one parent
    * `:name` - display name (defaults to the last identity value)
    * `:execution_id`, `:status`, `:cache_status`, `:duration_ms`
    * `:git_branch`, `:git_commit_sha`, `:is_ci`, `:observed_at`

  Never reads. Rows go through the ingestion buffer.
  """
  def record([]), do: :ok

  def record(observations) when is_list(observations) do
    now = NaiveDateTime.utc_now()

    observations
    |> Enum.map(&observation_row(&1, now))
    |> Observation.Buffer.insert_all()

    :ok
  end

  defp observation_row(observation, now) do
    %{project_id: project_id, system: system, kind: kind, identity: identity} = observation
    entity_id = Identity.id(project_id, system, kind, identity)
    parent_id = to_string(Map.get(observation, :parent_id) || "")

    %{
      project_id: project_id,
      system: Atom.to_string(system),
      kind: kind,
      entity_id: entity_id,
      observed_at: observed_at(Map.get(observation, :observed_at), now),
      id: Identity.observation_id(entity_id, parent_id, Map.get(observation, :discriminator, 0)),
      name: display_name(observation, system, kind, identity),
      identity: Identity.encode(system, kind, identity),
      parent_id: parent_id,
      execution_id: to_string(Map.get(observation, :execution_id) || ""),
      status: allowed(Map.get(observation, :status), @statuses, "unknown"),
      cache_status: allowed(Map.get(observation, :cache_status), @cache_statuses, "none"),
      duration_ms: duration_ms(Map.get(observation, :duration_ms)),
      git_branch: Map.get(observation, :git_branch) || "",
      git_commit_sha: Map.get(observation, :git_commit_sha) || "",
      is_ci: Map.get(observation, :is_ci),
      inserted_at: now
    }
  end

  defp display_name(observation, system, kind, identity) do
    case Map.get(observation, :name) do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        system |> Identity.normalize(kind, identity) |> List.last() |> elem(1)
    end
  end

  defp allowed(value, allowed, default) do
    value = if is_atom(value) and not is_nil(value), do: Atom.to_string(value), else: value
    if value in allowed, do: value, else: default
  end

  defp duration_ms(value) when is_integer(value) and value >= 0, do: min(value, @max_uint64)
  defp duration_ms(value) when is_float(value) and value >= 0, do: value |> round() |> min(@max_uint64)
  defp duration_ms(_value), do: nil

  # Client clocks are untrusted: a timestamp far in the future or past would
  # misplace the observation, so it falls back to ingestion time.
  defp observed_at(value, now) do
    naive =
      case value do
        %DateTime{} = datetime -> DateTime.to_naive(datetime)
        %NaiveDateTime{} = naive -> naive
        _ -> now
      end

    upper = NaiveDateTime.add(now, @future_tolerance_seconds, :second)
    lower = NaiveDateTime.add(now, -@past_tolerance_days, :day)

    naive =
      if NaiveDateTime.after?(naive, upper) or NaiveDateTime.before?(naive, lower), do: now, else: naive

    %{naive | microsecond: {elem(naive.microsecond, 0), 6}}
  end

  @doc """
  Lists entities of a kind from the catalog, sorted by last seen (default) or
  name. Entries are entity maps plus `observations`, the number of
  deduplicated observations in the window.

  Without environment or branch filters the window matches entities whose
  first/last seen range overlaps it. With them, only entities that have a
  matching observation in the window are listed.

  Options: `:start_datetime`, `:end_datetime`, `:environment` (`"any"`, `"ci"`,
  `"local"`), `:branch`, `:search`, `:page`, `:page_size`, `:sort_by`
  (`"last_seen_at"` or `"name"`), `:sort_order` (`"asc"` or `"desc"`).
  """
  def list(project_id, system, kind, opts \\ []) do
    case Identity.resolve(system, kind) do
      {:ok, {system, kind, _fields}} -> do_list(project_id, system, kind, opts)
      :error -> {[], pagination_metadata(0, page(opts), page_size(opts))}
    end
  end

  defp do_list(project_id, system, kind, opts) do
    {start_at, end_at} = window(opts)
    page = page(opts)
    page_size = page_size(opts)
    search = opts |> Keyword.get(:search) |> blank_to_nil()
    {observation_filters, filter_params} = observation_filters(opts)

    params =
      Map.merge(filter_params, %{
        project_id: project_id,
        system: Atom.to_string(system),
        kind: kind,
        start_at: start_at,
        end_at: end_at,
        search: search || "",
        limit: page_size,
        offset: (page - 1) * page_size
      })

    catalog = """
    SELECT
      toString(entity_id) AS entity,
      any(identity) AS entity_identity,
      argMaxMerge(name) AS entity_name,
      min(first_seen_at) AS first_seen,
      max(last_seen_at) AS last_seen
    FROM build_entities
    WHERE #{entity_range()}
    GROUP BY entity_id
    HAVING last_seen >= {start_at:DateTime64(6)} AND first_seen < {end_at:DateTime64(6)}
      #{if search, do: "AND (positionCaseInsensitive(entity_name, {search:String}) > 0 OR positionCaseInsensitive(entity_identity, {search:String}) > 0)", else: ""}
    """

    catalog = filtered_catalog(catalog, observation_filters)

    {:ok, %{rows: rows}} =
      bounded_query(
        """
        SELECT *, count() OVER () AS total_count FROM (#{catalog})
        ORDER BY #{list_order(opts)}
        LIMIT {limit:UInt32} OFFSET {offset:UInt32}
        """,
        params,
        @kind_scan_settings
      )

    {total_count, rows} = page_count(rows, catalog, params, @kind_scan_settings)
    entries = inventory_entries(rows, params, observation_filters)

    {entries, pagination_metadata(total_count, page, page_size)}
  end

  defp filtered_catalog(catalog, []), do: catalog

  defp filtered_catalog(catalog, filters) do
    # Catalog ranges include every version, so candidates cannot exclude a
    # latest observation in the window. Restrict only whole replacement groups.
    candidates = "AND entity_id IN (SELECT toUUID(entity) FROM (#{catalog}))"

    """
    SELECT catalog.*, matching.observations
    FROM (#{catalog}) AS catalog
    INNER JOIN (
      SELECT toString(entity_id) AS entity, count() AS observations
      FROM (#{latest_cohorts(candidates)})
      WHERE #{time_range()} AND #{Enum.join(filters, " AND ")}
      GROUP BY entity_id
    ) AS matching USING (entity)
    """
  end

  defp inventory_entries(rows, params, []) do
    entities = Enum.map(rows, &entity_from_row/1)
    counts = observation_counts(params, [], Enum.map(entities, & &1.id))
    Enum.map(entities, &Map.put(&1, :observations, Map.get(counts, &1.id, 0)))
  end

  defp inventory_entries(rows, _params, _filters) do
    Enum.map(rows, fn row ->
      {count, catalog_fields} = List.pop_at(row, -1)
      Map.put(entity_from_row(catalog_fields), :observations, count)
    end)
  end

  defp page_count([], cohort, params, settings) do
    {:ok, %{rows: [[count]]}} = bounded_query("SELECT count() FROM (#{cohort})", params, settings)
    {count, []}
  end

  defp page_count(rows, _cohort, _params, _settings) do
    {List.last(hd(rows)), Enum.map(rows, &Enum.drop(&1, -1))}
  end

  defp list_order(opts) do
    direction = if Keyword.get(opts, :sort_order) == "asc", do: "ASC", else: "DESC"

    case Keyword.get(opts, :sort_by) do
      "name" -> "entity_name #{direction}, entity ASC"
      _ -> "last_seen #{direction}, entity ASC"
    end
  end

  defp observation_counts(_params, _filters, []), do: %{}

  defp observation_counts(params, filters, ids) do
    {:ok, %{rows: rows}} =
      bounded_query(
        """
        SELECT toString(entity_id), count()
        FROM (#{latest_observations("AND entity_id IN {ids:Array(UUID)}")})
        #{where([time_range() | filters])}
        GROUP BY entity_id
        """,
        Map.put(params, :ids, ids),
        @entity_read_settings
      )

    Map.new(rows, fn [id, count] -> {id, count} end)
  end

  @doc """
  Gets one entity from the catalog. Returns `{:error, :not_found}` for unknown
  IDs, IDs from another project, and invalid system/kind pairs.
  """
  def get(project_id, system, kind, id) do
    with {:ok, {system, kind, _fields}} <- Identity.resolve(system, kind),
         {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, %{rows: [row]}} <-
           bounded_query(
             """
             SELECT
               toString(entity_id) AS entity,
               any(identity) AS entity_identity,
               argMaxMerge(name) AS entity_name,
               min(first_seen_at) AS first_seen,
               max(last_seen_at) AS last_seen
             FROM build_entities
             WHERE #{entity_range()} AND entity_id = {entity_id:UUID}
             GROUP BY entity_id
             """,
             %{project_id: project_id, system: Atom.to_string(system), kind: kind, entity_id: id},
             @entity_read_settings
           ) do
      {:ok, entity_from_row(row)}
    else
      :error -> {:error, :not_found}
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, error} -> raise error
    end
  end

  @doc """
  The subset of `invocation_ids` that have a Bazel invocation in the project.

  Cache-only Bazel clients report cache events without a Build Event Protocol
  stream, so a cache action observation's parent invocation may not exist.
  Callers use this to avoid linking to a missing invocation for one page of
  history at a time: at most #{@max_parent_lookups} distinct IDs, answered by a
  single query.
  """
  def available_bazel_invocations(project_id, invocation_ids) when is_integer(project_id) and is_list(invocation_ids) do
    ids = invocation_ids |> Enum.filter(&(is_binary(&1) and &1 != "")) |> Enum.uniq()

    cond do
      ids == [] ->
        MapSet.new()

      length(ids) > @max_parent_lookups ->
        raise ArgumentError, "expected at most #{@max_parent_lookups} invocation IDs, got #{length(ids)}"

      true ->
        {:ok, %{rows: rows}} =
          bounded_query(
            """
            SELECT DISTINCT invocation_id
            FROM bazel_invocations
            WHERE project_id = {project_id:Int64} AND invocation_id IN {ids:Array(String)}
            """,
            %{project_id: project_id, ids: ids},
            @entity_read_settings
          )

        MapSet.new(rows, fn [id] -> id end)
    end
  end

  @doc """
  Native context for each parent build, invocation, command or run of one page
  of history: at most #{@max_parent_lookups} distinct valid IDs, answered by one
  bounded lookup against the native parent plus one batch of account names.

  Returns `%{parent_id => context}`, keyed by the IDs as given, with an entry
  only for parents that exist in the project. A context has:

    * `:label` - the human-readable name the native run pages show, or `nil`
      when the parent recorded none. It is never replaced by an ID or a guess.
      Gradle builds use the root project name; Xcode builds the scheme;
      Xcode commands the raw command name (for example `"generate"`); Mix
      builds the literal `"mix compile"`; Once runs their safe
      `command_display`; Bazel invocations the raw Bazel command (for example
      `"build"`). Surfaces format commands.
    * `:ran_by_name` - the recorded actor, as described in
      `parent_actor_names/4`, or `nil`. Always `nil` for Bazel.
    * `:tags` - Gradle only: the build's `custom_tags`.
    * `:command_arguments` - Xcode modules only: the command's recorded
      `command_arguments`, or `nil`, for native command rendering.
    * `:target_patterns` - Bazel only: the invocation's recorded target
      patterns, for native requested-command rendering.

  `label` stays the raw native value; these fields are the existing recorded
  inputs native pages render commands from, read in the same query.

  The latest version of each parent decides every field, including a version
  that cleared one. UUID parents that are empty or malformed are skipped; Once
  run IDs and Bazel invocation IDs are kept as strings. An invalid
  system/kind pair returns `%{}`. The ClickHouse lookups run under the entity
  read limits and raise `Tuist.BuildEntities.QueryLimitError`.
  """
  def parent_contexts(project_id, system, kind, parent_ids) when is_integer(project_id) and is_list(parent_ids) do
    case Identity.resolve(system, kind) do
      {:ok, {system, kind, _fields}} -> resolve_parent_contexts(project_id, parent_source(system, kind), parent_ids)
      :error -> %{}
    end
  end

  @doc """
  The name of the user account that ran each parent of one page of history:
  `%{parent_id => account_name}` for at most #{@max_parent_lookups} distinct
  valid IDs.

  It reports the attribution the native parent recorded, the same one the
  native build run pages display, including a personal project's owner when
  that account was recorded. A parent is absent when it does not exist in the
  project, recorded no actor, or its recorded actor is zero, deleted or an
  organization. Nothing is derived when attribution is missing: no fallback
  to the project's account or the viewer, and no recovery of credential
  details older reports never stored.

    * Gradle tasks, Mix files and modules, and Xcode cache actions read the
      build's recorded `account_id`.
    * Xcode modules read the generate or cache command's attributed `user_id`.
    * Once actions read the run's recorded credential `account_id`.
    * Bazel has no trustworthy actor, so it always returns `%{}`.

  Each parent's latest version decides, including a later version that
  cleared the actor. Raises `Tuist.BuildEntities.QueryLimitError` like
  `parent_contexts/4`, which it is built on.
  """
  def parent_actor_names(project_id, system, kind, parent_ids) when is_integer(project_id) and is_list(parent_ids) do
    case Identity.resolve(system, kind) do
      {:ok, {:bazel, _kind, _fields}} ->
        %{}

      {:ok, {system, kind, _fields}} ->
        project_id
        |> resolve_parent_contexts(parent_source(system, kind), parent_ids)
        |> Enum.flat_map(fn
          {id, %{ran_by_name: name}} when is_binary(name) -> [{id, name}]
          _context -> []
        end)
        |> Map.new()

      :error ->
        %{}
    end
  end

  defp resolve_parent_contexts(_project_id, :none, _parent_ids), do: %{}

  defp resolve_parent_contexts(project_id, source, parent_ids) do
    keys = parent_keys(source, parent_ids)

    cond do
      keys == %{} ->
        %{}

      map_size(keys) > @max_parent_lookups ->
        raise ArgumentError, "expected at most #{@max_parent_lookups} parent IDs, got #{map_size(keys)}"

      true ->
        project_id
        |> parent_records(source, Map.keys(keys))
        |> with_actor_names()
        |> Enum.flat_map(fn {key, context} -> Enum.map(Map.fetch!(keys, key), &{&1, context}) end)
        |> Map.new()
    end
  end

  defp parent_source(:gradle, "task"), do: :gradle_build
  defp parent_source(:mix, _kind), do: :mix_build
  defp parent_source(:xcode, "cache_action"), do: :xcode_build
  defp parent_source(:xcode, "module"), do: :command_event
  defp parent_source(:once, "action"), do: :once_run
  defp parent_source(:bazel, "cache_action"), do: :bazel_invocation
  defp parent_source(_system, _kind), do: :none

  # Normalized lookup key => the caller's IDs that map to it.
  defp parent_keys(:once_run, parent_ids) do
    parent_ids
    |> Enum.filter(&once_run_id?/1)
    |> Enum.group_by(& &1)
  end

  defp parent_keys(:bazel_invocation, parent_ids) do
    parent_ids
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.group_by(& &1)
  end

  defp parent_keys(_source, parent_ids) do
    parent_ids
    |> Enum.flat_map(fn id ->
      case parent_uuid(id) do
        {:ok, uuid} -> [{uuid, id}]
        :error -> []
      end
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # `once_runs.run_id` is a `varchar(128)`, and Postgres rejects NUL bytes and
  # invalid UTF-8 even in a lookup, so only IDs that could be stored are sent.
  defp once_run_id?(id) when is_binary(id) and id != "" and byte_size(id) <= 512,
    do: String.valid?(id) and not String.contains?(id, <<0>>) and String.length(id) <= 128

  defp once_run_id?(_id), do: false

  defp parent_uuid(id) when is_binary(id) and byte_size(id) == 36, do: Ecto.UUID.cast(id)
  defp parent_uuid(_id), do: :error

  # Each source returns `{key, %{label: ..., actor: ...}}` for the parents that
  # exist, where `actor` is `{:account, id}`, `{:user, id}`, `{:name, name}`
  # or `nil`. `argMax` ignores NULL values, so the latest version is selected as
  # one tuple: a later version that cleared a nullable field must win.
  defp parent_records(project_id, :gradle_build, uuids) do
    project_id
    |> latest_parent_rows("gradle_builds", "id", "account_id, root_project_name, custom_tags", "inserted_at", uuids)
    |> Enum.map(fn [id, account_id, root_project_name, tags] ->
      {id, %{label: blank_to_nil(root_project_name), tags: tags || [], actor: account_actor(account_id)}}
    end)
  end

  defp parent_records(project_id, :mix_build, uuids) do
    project_id
    |> latest_parent_rows("mix_builds", "id", "account_id", "inserted_at", uuids)
    |> Enum.map(fn [id, account_id] -> {id, %{label: "mix compile", actor: account_actor(account_id)}} end)
  end

  defp parent_records(project_id, :xcode_build, uuids) do
    project_id
    |> latest_parent_rows("build_runs", "id", "account_id, scheme", "updated_at", uuids)
    |> Enum.map(fn [id, account_id, scheme] ->
      {id, %{label: blank_to_nil(scheme), actor: account_actor(account_id)}}
    end)
  end

  defp parent_records(project_id, :command_event, uuids) do
    project_id
    |> latest_parent_rows("command_events", "id", "user_id, name, command_arguments", "updated_at", uuids)
    |> Enum.map(fn [id, user_id, name, command_arguments] ->
      actor = if is_integer(user_id) and user_id > 0, do: {:user, user_id}
      {id, %{label: blank_to_nil(name), command_arguments: blank_to_nil(command_arguments), actor: actor}}
    end)
  end

  defp parent_records(project_id, :bazel_invocation, invocation_ids) do
    columns = "command, target_patterns"

    project_id
    |> latest_parent_rows("bazel_invocations", "invocation_id", columns, "inserted_at", invocation_ids)
    |> Enum.map(fn [id, command, target_patterns] ->
      {id, %{label: blank_to_nil(command), target_patterns: target_patterns || [], actor: nil}}
    end)
  end

  defp parent_records(project_id, :once_run, run_ids) do
    query =
      from(r in Run,
        left_join: a in Account,
        on: a.id == r.account_id and not is_nil(a.user_id),
        where: r.project_id == ^project_id and r.run_id in ^run_ids,
        select: {r.run_id, r.command_display, a.name}
      )

    query
    |> Repo.all()
    |> Enum.map(fn {run_id, command_display, name} ->
      {run_id, %{label: blank_to_nil(command_display), actor: name && {:name, name}}}
    end)
  end

  # Table, key, column and version names are fixed by `parent_records/3`;
  # nothing here comes from input.
  defp latest_parent_rows(project_id, table, key, columns, version, ids) do
    key_type = if key == "id", do: "UUID", else: "String"
    count = columns |> String.split(",") |> length()
    fields = Enum.map_join(1..count, ", ", &"latest.#{&1}")

    {:ok, %{rows: rows}} =
      bounded_query(
        """
        SELECT parent, #{fields}
        FROM (
          SELECT toString(#{key}) AS parent, argMax(tuple(#{columns}), #{version}) AS latest
          FROM #{table}
          WHERE project_id = {project_id:Int64} AND #{key} IN {ids:Array(#{key_type})}
          GROUP BY #{key}
        )
        """,
        %{project_id: project_id, ids: ids},
        @entity_read_settings
      )

    rows
  end

  defp account_actor(account_id) when is_integer(account_id) and account_id > 0, do: {:account, account_id}
  defp account_actor(_account_id), do: nil

  # Resolves recorded actors with at most one Postgres query per actor kind.
  # Only user accounts are named.
  defp with_actor_names(records) do
    account_names = actor_names(records, :account, &user_account_names/1)
    user_names = actor_names(records, :user, &user_names/1)

    Enum.map(records, fn {key, record} ->
      ran_by_name =
        case record.actor do
          {:account, id} -> Map.get(account_names, id)
          {:user, id} -> Map.get(user_names, id)
          {:name, name} -> name
          nil -> nil
        end

      {key, record |> Map.delete(:actor) |> Map.put(:ran_by_name, ran_by_name)}
    end)
  end

  defp actor_names(records, kind, lookup) do
    ids = for {_key, %{actor: {^kind, id}}} <- records, uniq: true, do: id
    if ids == [], do: %{}, else: lookup.(ids)
  end

  defp user_account_names(account_ids) do
    Map.new(Repo.all(from(a in Account, where: a.id in ^account_ids and not is_nil(a.user_id), select: {a.id, a.name})))
  end

  defp user_names(user_ids) do
    Map.new(
      Repo.all(
        from(u in User,
          join: a in Account,
          on: a.user_id == u.id,
          where: u.id in ^user_ids,
          select: {u.id, a.name}
        )
      )
    )
  end

  @doc """
  Lists deduplicated observations of one entity, newest first.

  Pagination is by page, or by keyset when `:after` or `:before` (cursors from
  a previous result's metadata) is given. Keyset pages report `current_page`
  as `nil`.

  Options: `:start_datetime`, `:end_datetime`, `:environment`, `:branch`,
  `:cache_status`, `:search`, `:filters`, `:sort_by` (`"observed_at"` or
  `"duration_ms"`), `:sort_order`, `:page`, `:page_size`, `:after`, `:before`.
  Search matches branch, commit and native run/execution identifiers. Table
  filters accept only branch, outcome and cache outcome with fixed operators.
  Non-default ordering uses bounded numbered pages rather than time cursors.
  """
  def history(project_id, system, kind, id, opts \\ []) do
    page_size = page_size(opts)

    case scope(project_id, system, kind, id, opts) do
      {:ok, params, filters} ->
        {table_filters, table_params} = history_filters(opts)
        do_history(Map.merge(params, table_params), filters ++ table_filters, page_size, opts)

      :error ->
        {[], pagination_metadata(0, page(opts), page_size)}
    end
  end

  defp do_history(params, filters, page_size, opts) do
    deduped = deduplicated_observations(filters)

    cursor_order? = cursor_order?(opts)
    {mode, cursor} = if cursor_order?, do: cursor_mode(opts), else: {nil, nil}
    page = min(page(opts), 10_000)

    {{keyset_clause, keyset_params}, order, offset} = keyset(mode, cursor, (page - 1) * page_size)

    sort = history_order(opts, cursor_order?, order)

    {:ok, %{rows: rows}} =
      bounded_query(
        """
        SELECT toString(id), observed_at, parent_id, execution_id, status, cache_status,
               duration_ms, git_branch, git_commit_sha, is_ci, total_count
        FROM (SELECT *, count() OVER () AS total_count FROM (#{deduped}))
        #{keyset_clause}
        ORDER BY #{sort}
        LIMIT {limit:UInt32} OFFSET {offset:UInt32}
        """,
        params |> Map.merge(keyset_params) |> Map.merge(%{limit: page_size + 1, offset: offset}),
        @entity_read_settings
      )

    {total_count, rows} = page_count(rows, deduped, params, @entity_read_settings)
    more? = length(rows) > page_size
    rows = Enum.take(rows, page_size)
    rows = if cursor_order? and order == "ASC", do: Enum.reverse(rows), else: rows
    observations = Enum.map(rows, &observation_from_row/1)

    metadata = history_metadata(mode, more?, pagination_metadata(total_count, page, page_size))

    metadata =
      Map.merge(metadata, %{
        after: if(cursor_order? and metadata.has_next_page, do: observations |> List.last() |> encode_cursor()),
        before: if(cursor_order? and metadata.has_previous_page, do: observations |> List.first() |> encode_cursor())
      })

    {observations, metadata}
  end

  defp history_order(_opts, true, order), do: "observed_at #{order}, id #{order}"

  defp history_order(opts, false, _order) do
    field = if Keyword.get(opts, :sort_by) == "duration_ms", do: "duration_ms", else: "observed_at"
    direction = if Keyword.get(opts, :sort_order) == "asc", do: "ASC", else: "DESC"
    "#{field} #{direction} NULLS LAST, observed_at DESC, id DESC"
  end

  defp cursor_order?(opts),
    do: Keyword.get(opts, :sort_by, "observed_at") == "observed_at" and Keyword.get(opts, :sort_order, "desc") == "desc"

  defp history_filters(opts) do
    filters =
      opts
      |> Keyword.get(:filters, [])
      |> Enum.with_index()
      |> Enum.flat_map(fn {filter, index} -> history_filter(filter, index) end)

    filters =
      case opts |> Keyword.get(:search) |> blank_to_nil() do
        nil ->
          filters

        search ->
          [
            {"(positionCaseInsensitive(git_branch, {history_search:String}) > 0 OR " <>
               "positionCaseInsensitive(git_commit_sha, {history_search:String}) > 0 OR " <>
               "positionCaseInsensitive(parent_id, {history_search:String}) > 0 OR " <>
               "positionCaseInsensitive(execution_id, {history_search:String}) > 0)", %{history_search: search}}
            | filters
          ]
      end

    {Enum.map(filters, &elem(&1, 0)), Enum.reduce(filters, %{}, &Map.merge(elem(&1, 1), &2))}
  end

  defp history_filter(%{value: value}, _index) when value in [nil, ""], do: []

  defp history_filter(%{field: field, op: op, value: value}, index) when is_binary(value) do
    column = history_filter_column(field, value)

    parameter = "history_filter_#{index}"
    params = %{parameter => value}

    case {column, op} do
      {nil, _} -> []
      {column, :==} -> [{"#{column} = {#{parameter}:String}", params}]
      {column, :!=} when field != :git_branch -> [{"#{column} != {#{parameter}:String}", params}]
      {"git_branch", :=~} -> [{"positionCaseInsensitive(git_branch, {#{parameter}:String}) > 0", params}]
      {"git_branch", :not_ilike} -> [{"positionCaseInsensitive(git_branch, {#{parameter}:String}) = 0", params}]
      _ -> []
    end
  end

  defp history_filter(_filter, _index), do: []

  defp history_filter_column(:git_branch, _value), do: "git_branch"
  defp history_filter_column(:status, value) when value in @statuses, do: "status"
  defp history_filter_column(:cache_status, value) when value in @cache_statuses, do: "cache_status"
  defp history_filter_column(_field, _value), do: nil

  defp keyset(:after, {at, cursor_id}, _offset),
    do:
      {{"WHERE (observed_at, id) < ({cursor_at:DateTime64(6)}, {cursor_id:UUID})",
        %{cursor_at: at, cursor_id: cursor_id}}, "DESC", 0}

  defp keyset(:before, {at, cursor_id}, _offset),
    do:
      {{"WHERE (observed_at, id) > ({cursor_at:DateTime64(6)}, {cursor_id:UUID})",
        %{cursor_at: at, cursor_id: cursor_id}}, "ASC", 0}

  defp keyset(_mode, _cursor, offset), do: {{"", %{}}, "DESC", offset}

  defp history_metadata(:after, more?, metadata),
    do: %{metadata | current_page: nil, has_previous_page: true, has_next_page: more?}

  defp history_metadata(:before, more?, metadata),
    do: %{metadata | current_page: nil, has_previous_page: more?, has_next_page: true}

  defp history_metadata(nil, _more?, metadata), do: metadata

  defp cursor_mode(opts) do
    cond do
      cursor = decode_cursor(Keyword.get(opts, :after)) -> {:after, cursor}
      cursor = decode_cursor(Keyword.get(opts, :before)) -> {:before, cursor}
      true -> {nil, nil}
    end
  end

  defp encode_cursor(nil), do: nil

  defp encode_cursor(%{observed_at: observed_at, id: id}) do
    Base.url_encode64("#{DateTime.to_unix(observed_at, :microsecond)}:#{id}", padding: false)
  end

  defp decode_cursor(cursor) when is_binary(cursor) and cursor != "" do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [microseconds, id] <- String.split(decoded, ":", parts: 2),
         {microseconds, ""} <- Integer.parse(microseconds),
         {:ok, at} <- DateTime.from_unix(microseconds, :microsecond),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {at, id}
    else
      _ -> nil
    end
  end

  defp decode_cursor(_cursor), do: nil

  @doc """
  Metrics for one entity over the window (`total`), the equally long window
  before it (`previous`), and one zero-filled point per UTC day (`points`).

  Metrics: `observations`, `hits`, `misses`, `hit_rate` (percentage, `nil`
  without cacheable observations), `failures`, `duration_samples`,
  `avg_duration_ms`, `p50_duration_ms`, `p90_duration_ms`, `p99_duration_ms`
  (`nil` without durations). Durations cover every observation with a
  duration, and `duration_samples` counts exactly those, so it can be lower
  than `observations` (Gradle hits and skips, missing native timings). Pass
  `:cache_status` to restrict durations, e.g. `"miss"` for executed work.

  Options: `:start_datetime`, `:end_datetime`, `:environment`, `:branch`,
  `:cache_status`.
  """
  def analytics(project_id, system, kind, id, opts \\ []) do
    {start_at, end_at} = window(opts)
    previous_start_at = DateTime.add(start_at, -DateTime.diff(end_at, start_at, :microsecond), :microsecond)

    case scope(project_id, system, kind, id, Keyword.put(opts, :start_datetime, previous_start_at)) do
      {:ok, params, filters} ->
        params = Map.put(params, :current_start_at, start_at)
        deduped = deduplicated_observations(filters)

        {:ok, %{rows: rows}} =
          bounded_query(
            """
            SELECT GROUPING(day) AS period, current, toString(day), #{metrics_select()}
            FROM (
              SELECT *, observed_at >= {current_start_at:DateTime64(6)} AS current,
                     toDate(observed_at) AS day
              FROM (#{deduped})
            )
            GROUP BY GROUPING SETS ((current), (current, day))
            """,
            params,
            @entity_read_settings
          )

        periods =
          Map.new(for [1, current, _date | metrics] <- rows, do: {current in [true, 1], metrics_from_row(metrics)})

        points =
          Map.new(for [0, current, date | metrics] <- rows, current in [true, 1], do: {date, metrics_from_row(metrics)})

        %{
          total: Map.get(periods, true, empty_metrics()),
          previous: Map.get(periods, false, empty_metrics()),
          points:
            start_at
            |> DateTime.to_date()
            |> Date.range(end_at |> DateTime.add(-1, :microsecond) |> DateTime.to_date())
            |> Enum.map(fn date ->
              date = Date.to_iso8601(date)
              Map.put(Map.get(points, date, empty_metrics()), :date, date)
            end)
        }

      :error ->
        %{total: empty_metrics(), previous: empty_metrics(), points: []}
    end
  end

  @doc """
  The newest measured observations of one entity in the window, for a
  duration scatter chart.

  Observations are deduplicated to their latest version before the period,
  environment, branch and cache-status filters apply, and only then are those
  without a duration dropped, so a replay that cleared or moved a duration is
  never plotted from a superseded version. Rows are ordered by `observed_at`
  and `id`, newest first, and capped at #{@max_scatter_observations}.

  Returns `%{rows: observations, truncated: boolean, oldest_entry: naive}`.
  `rows` are observation maps as in `history/5`. `truncated` is `true` when
  older measured observations in the window were left out. `oldest_entry` is
  the oldest included observation's time as a UTC `NaiveDateTime`, or `nil`
  when there are no rows. An invalid system, kind or ID returns no rows.

  Options: `:start_datetime`, `:end_datetime`, `:environment`, `:branch`,
  `:cache_status`, and `:limit` to lower the cap.
  """
  def duration_scatter(project_id, system, kind, id, opts \\ []) do
    limit = scatter_limit(opts)

    case scope(project_id, system, kind, id, opts) do
      {:ok, params, filters} ->
        {:ok, %{rows: rows}} =
          bounded_query(
            """
            SELECT toString(id), observed_at, parent_id, execution_id, status, cache_status,
                   duration_ms, git_branch, git_commit_sha, is_ci
            FROM (#{deduplicated_observations(filters ++ ["duration_ms IS NOT NULL"])})
            ORDER BY observed_at DESC, id DESC
            LIMIT {limit:UInt32}
            """,
            Map.put(params, :limit, limit + 1),
            @entity_read_settings
          )

        observations = rows |> Enum.take(limit) |> Enum.map(&observation_from_row/1)

        %{
          rows: observations,
          truncated: length(rows) > limit,
          oldest_entry:
            case List.last(observations) do
              nil -> nil
              observation -> DateTime.to_naive(observation.observed_at)
            end
        }

      :error ->
        %{rows: [], truncated: false, oldest_entry: nil}
    end
  end

  defp scatter_limit(opts) do
    case Keyword.get(opts, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, @max_scatter_observations)
      _ -> @max_scatter_observations
    end
  end

  defp metrics_select do
    hit_statuses = Enum.map_join(@hit_statuses, ", ", &"'#{&1}'")

    """
    count() AS observations,
    countIf(cache_status IN (#{hit_statuses})) AS hits,
    countIf(cache_status = 'miss') AS misses,
    countIf(status = 'failure') AS failures,
    count(duration_ms) AS duration_samples,
    avgOrNull(duration_ms) AS avg_duration_ms,
    quantileOrNull(0.5)(duration_ms) AS p50_duration_ms,
    quantileOrNull(0.9)(duration_ms) AS p90_duration_ms,
    quantileOrNull(0.99)(duration_ms) AS p99_duration_ms
    """
  end

  defp metrics_from_row([observations, hits, misses, failures, duration_samples, avg, p50, p90, p99]) do
    %{
      observations: observations,
      hits: hits,
      misses: misses,
      hit_rate: hit_rate(hits, misses),
      failures: failures,
      duration_samples: duration_samples,
      avg_duration_ms: round_duration(avg),
      p50_duration_ms: round_duration(p50),
      p90_duration_ms: round_duration(p90),
      p99_duration_ms: round_duration(p99)
    }
  end

  defp empty_metrics, do: metrics_from_row([0, 0, 0, 0, 0, nil, nil, nil, nil])

  defp hit_rate(0, 0), do: nil
  defp hit_rate(hits, misses), do: Float.round(hits * 100 / (hits + misses), 1)

  defp round_duration(value) when is_number(value), do: round(value)
  defp round_duration(_value), do: nil

  defp scope(project_id, system, kind, id, opts) do
    with {:ok, {system, kind, _fields}} <- Identity.resolve(system, kind),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {start_at, end_at} = window(opts)
      {filters, filter_params} = observation_filters(opts)

      params =
        Map.merge(filter_params, %{
          project_id: project_id,
          system: Atom.to_string(system),
          kind: kind,
          entity_id: id,
          start_at: start_at,
          end_at: end_at
        })

      {:ok, params, filters}
    else
      _ -> :error
    end
  end

  defp deduplicated_observations(filters) do
    """
    SELECT * FROM (#{latest_observations("AND entity_id = {entity_id:UUID}")})
    #{where([time_range() | filters])}
    """
  end

  # FINAL merges replacement versions by the stable observation key, including
  # across insertion-month partitions. Never PREWHERE a time/cohort filter:
  # that would discard a correction before deciding which version wins. Key-only
  # PREWHERE selects complete replacement groups before loading payload columns.
  defp latest_observations(entity_filter) do
    """
    SELECT entity_id, id, observed_at, parent_id, execution_id, status, cache_status,
           duration_ms, git_branch, git_commit_sha, is_ci
    FROM build_entity_observations FINAL
    PREWHERE #{entity_range()} #{entity_filter}
    """
  end

  defp latest_cohorts(entity_filter) do
    """
    SELECT entity_id, observed_at, is_ci, git_branch, cache_status
    FROM build_entity_observations FINAL
    PREWHERE #{entity_range()} #{entity_filter}
    """
  end

  # Raises `QueryLimitError` only for the time and memory limits these settings
  # impose. Every other result, including other database errors, is returned as
  # is. The client waits a little longer than the server-side limit so the
  # server is the one that gives up.
  defp bounded_query(sql, params, settings) do
    timeout = to_timeout(second: Keyword.fetch!(settings, :max_execution_time) + 5)

    case ClickHouseRepo.query(sql, params, settings: settings, timeout: timeout) do
      {:error, %Ch.Error{code: code, message: message}} when code in @query_limit_codes and is_binary(message) ->
        raise QueryLimitError, code: code, message: message

      {:error, %Ch.Error{code: code}} when code in @query_limit_codes ->
        raise QueryLimitError, code: code

      result ->
        result
    end
  end

  defp observation_filters(opts) do
    environment =
      case Keyword.get(opts, :environment) do
        "ci" -> [{"is_ci = true", %{}}]
        "local" -> [{"is_ci = false", %{}}]
        _ -> []
      end

    branch =
      case opts |> Keyword.get(:branch) |> blank_to_nil() do
        nil -> []
        branch -> [{"git_branch = {branch:String}", %{branch: branch}}]
      end

    cache_status =
      case Keyword.get(opts, :cache_status) do
        "hit" -> [{"cache_status IN ('hit', 'hit_local', 'hit_remote')", %{}}]
        status when status in @cache_statuses -> [{"cache_status = {cache_status:String}", %{cache_status: status}}]
        _ -> []
      end

    filters = environment ++ branch ++ cache_status
    {Enum.map(filters, &elem(&1, 0)), Enum.reduce(filters, %{}, &Map.merge(elem(&1, 1), &2))}
  end

  defp where(filters), do: "WHERE " <> Enum.join(filters, " AND ")

  defp entity_range, do: "project_id = {project_id:Int64} AND system = {system:String} AND kind = {kind:String}"

  defp time_range, do: "observed_at >= {start_at:DateTime64(6)} AND observed_at < {end_at:DateTime64(6)}"

  defp window(opts) do
    end_at = Keyword.get(opts, :end_datetime) || DateTime.utc_now()
    start_at = Keyword.get(opts, :start_datetime) || DateTime.add(end_at, -@default_window_days, :day)
    {start_at, end_at}
  end

  defp page(opts) do
    case Keyword.get(opts, :page) do
      page when is_integer(page) and page > 0 -> page
      _ -> 1
    end
  end

  defp page_size(opts) do
    case Keyword.get(opts, :page_size) do
      size when is_integer(size) and size > 0 -> min(size, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp pagination_metadata(total_count, page, page_size) do
    total_pages = if total_count == 0, do: 0, else: div(total_count + page_size - 1, page_size)

    %{
      has_next_page: page < total_pages,
      has_previous_page: page > 1,
      current_page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  defp entity_from_row([id, identity, name, first_seen_at, last_seen_at]) do
    %{
      id: id,
      name: name,
      identity: JSON.decode!(identity),
      first_seen_at: to_datetime(first_seen_at),
      last_seen_at: to_datetime(last_seen_at)
    }
  end

  defp observation_from_row([
         id,
         observed_at,
         parent_id,
         execution_id,
         status,
         cache_status,
         duration_ms,
         git_branch,
         git_commit_sha,
         is_ci
       ]) do
    %{
      id: id,
      parent_id: parent_id,
      execution_id: execution_id,
      status: status,
      cache_status: cache_status,
      duration_ms: duration_ms,
      git_branch: git_branch,
      git_commit_sha: git_commit_sha,
      is_ci: is_ci,
      observed_at: to_datetime(observed_at)
    }
  end

  defp to_datetime(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")
  defp to_datetime(%DateTime{} = datetime), do: datetime

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
