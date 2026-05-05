defmodule Tuist.Bundles do
  @moduledoc """
  The Bundles context.
  """

  import Ecto.Query

  alias Tuist.Bundles.Artifact
  alias Tuist.Bundles.Bundle
  alias Tuist.Bundles.BundleThreshold
  alias Tuist.ClickHouseFlop
  alias Tuist.ClickHouseRepo
  alias Tuist.IngestRepo
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @doc """
  Creates a bundle with associated artifacts.

  Both the bundle row and its artifacts are written to ClickHouse. The
  artifacts insert happens first so a transient ClickHouse outage on
  either step surfaces before we report success and we never end up with
  a bundle row that has no artifacts.

  Returns `{:ok, bundle}` on success or `{:error, changeset}` if the
  input fails validation (invalid `type`, `supported_platforms`, or
  missing required fields).
  """
  def create_bundle(attrs \\ %{}, opts \\ []) do
    {artifacts, bundle_attrs} = Map.pop(attrs, :artifacts, [])
    bundle_id = Map.fetch!(attrs, :id)
    preload = Keyword.get(opts, :preload, [])

    # Truncate to seconds to match the precision PG `:utc_datetime` stored
    # before the CH cutover, so callers that compare against
    # second-truncated values (e.g. the dashboard date picker) keep
    # matching freshly-created bundles.
    timestamp = bundle_attrs |> Map.get(:inserted_at) |> truncate_timestamp()

    changeset =
      bundle_attrs
      |> Map.merge(%{inserted_at: timestamp, updated_at: timestamp})
      |> then(&Bundle.create_changeset(%Bundle{}, &1))

    if changeset.valid? do
      artifacts
      |> flatten_artifacts(bundle_id, nil, timestamp)
      |> insert_artifacts_to_clickhouse()

      IngestRepo.insert_all(Bundle, [bundle_row_from_changeset(changeset)])

      bundle =
        from(b in Bundle, where: b.id == type(^bundle_id, Ecto.UUID))
        |> ClickHouseRepo.one()
        |> decode_bundle()
        |> Repo.preload(preload)

      {:ok, bundle}
    else
      {:error, changeset}
    end
  end

  defp bundle_row_from_changeset(changeset) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.drop([:__meta__, :project, :uploaded_by_account, :artifacts])
  end

  defp insert_artifacts_to_clickhouse([]), do: :ok

  defp insert_artifacts_to_clickhouse(flattened) do
    IngestRepo.insert_all(Artifact, flattened)
    :ok
  end

  defp truncate_timestamp(nil), do: truncate_timestamp(DateTime.utc_now())

  defp truncate_timestamp(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> DateTime.to_naive() |> bump_usec_precision()
  end

  defp truncate_timestamp(%NaiveDateTime{} = ndt) do
    ndt |> NaiveDateTime.truncate(:second) |> bump_usec_precision()
  end

  defp bump_usec_precision(%NaiveDateTime{microsecond: {value, _}} = ndt) do
    %{ndt | microsecond: {value, 6}}
  end

  # ClickHouse stores enum-shaped fields as strings and timestamps as
  # `DateTime64(6)` (read back as `NaiveDateTime`); the rest of the
  # codebase works with atoms and `DateTime`, so normalize at every
  # read boundary that returns a `%Bundle{}` struct.
  defp decode_bundle(nil), do: nil

  defp decode_bundle(%Bundle{} = bundle) do
    %{
      bundle
      | type: decode_type(bundle.type),
        supported_platforms: Enum.map(bundle.supported_platforms || [], &String.to_existing_atom/1),
        inserted_at: from_naive_usec(bundle.inserted_at),
        updated_at: from_naive_usec(bundle.updated_at)
    }
  end

  defp decode_type(nil), do: nil
  defp decode_type(value) when is_atom(value), do: value
  defp decode_type(value) when is_binary(value), do: String.to_existing_atom(value)

  defp from_naive_usec(nil), do: nil
  defp from_naive_usec(%DateTime{} = dt), do: dt
  defp from_naive_usec(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp decode_bundles(bundles) when is_list(bundles), do: Enum.map(bundles, &decode_bundle/1)

  @doc """
  Gets a single bundle.
  """
  def get_bundle(id, opts \\ []) do
    preload = opts |> Keyword.get(:preload, []) |> drop_artifacts_preload()
    project_id = Keyword.get(opts, :project_id)

    query =
      then(
        from(b in Bundle, where: b.id == type(^id, Ecto.UUID)),
        &if(is_nil(project_id), do: &1, else: where(&1, [b], b.project_id == ^project_id))
      )

    case ClickHouseRepo.one(query) do
      nil ->
        {:error, :not_found}

      bundle ->
        bundle = bundle |> decode_bundle() |> Repo.preload(preload)
        {:ok, %{bundle | artifacts: bundle_artifacts(bundle)}}
    end
  end

  # `:artifacts` is loaded from ClickHouse via `bundle_artifacts/1`, so
  # strip it from the preload list to avoid `Repo.preload` issuing a
  # Postgres query against the (no-longer-existing) PG `artifacts` table.
  defp drop_artifacts_preload(:artifacts), do: []
  defp drop_artifacts_preload({:artifacts, _}), do: []

  defp drop_artifacts_preload(preload) when is_list(preload) do
    Enum.reject(preload, fn
      :artifacts -> true
      {:artifacts, _} -> true
      _ -> false
    end)
  end

  defp drop_artifacts_preload(other), do: other

  def get_bundle_artifact_tree(bundle_id) do
    from(a in Artifact,
      where: a.bundle_id == type(^bundle_id, Ecto.UUID),
      order_by: [asc: a.path]
    )
    |> ClickHouseRepo.all()
    |> Enum.map(&decode_artifact_type/1)
  end

  defp decode_artifact_type(%{artifact_type: type} = artifact) when is_binary(type) do
    %{artifact | artifact_type: String.to_existing_atom(type)}
  end

  defp decode_artifact_type(artifact), do: artifact

  defp bundle_artifacts(%Bundle{id: id}) do
    all_artifacts =
      from(a in Artifact,
        where: a.bundle_id == type(^id, Ecto.UUID),
        select: %{
          id: a.id,
          artifact_type: a.artifact_type,
          path: a.path,
          size: a.size,
          shasum: a.shasum,
          artifact_id: a.artifact_id,
          bundle_id: a.bundle_id,
          inserted_at: a.inserted_at,
          updated_at: a.updated_at
        }
      )
      |> ClickHouseRepo.all()
      |> Enum.map(&decode_artifact_type/1)

    # Filter top-level artifacts (those with no parent)
    top_level_artifacts =
      Enum.filter(all_artifacts, fn artifact -> is_nil(artifact.artifact_id) end)

    # Group child artifacts by their parent ID for efficient lookup
    artifacts_by_parent =
      all_artifacts
      |> Enum.filter(fn artifact -> !is_nil(artifact.artifact_id) end)
      |> Enum.group_by(fn artifact -> artifact.artifact_id end)

    # Build the tree structure in memory
    build_nested_structure(top_level_artifacts, artifacts_by_parent)
  end

  defp build_nested_structure(top_level_artifacts, artifacts_by_parent) do
    # Create a map of all artifacts for quick lookup
    all_artifacts = top_level_artifacts ++ List.flatten(Map.values(artifacts_by_parent))
    artifacts_by_id = Map.new(all_artifacts, &{&1.id, &1})

    # Recursive function to build the tree
    build_tree = fn
      build_tree, parent_id ->
        # Get direct children of this parent
        children =
          artifacts_by_parent
          |> Map.get(parent_id, [])
          |> Enum.map(fn child -> Map.put(child, :children, []) end)

        parent = Map.get(artifacts_by_id, parent_id)

        children_total_size = Enum.reduce(children, 0, fn child, sum -> sum + child.size end)

        children =
          if !Enum.empty?(children) && children_total_size < parent.size do
            missing_size = parent.size - children_total_size

            unknown_child = %{
              id: UUIDv7.generate(),
              size: missing_size,
              path: parent.path <> "/Unknown",
              children: [],
              artifact_type: :unknown,
              shasum: UUIDv7.generate(),
              artifact_id: parent.id
            }

            [unknown_child | children]
          else
            children
          end

        children = map_artifacts_with_collapsed(children)

        # Recursively process each child
        Enum.map(children, fn child ->
          child_children = build_tree.(build_tree, child.id)
          Map.put(child, :children, child_children)
        end)
    end

    # Process each top-level artifact
    top_level_artifacts
    |> map_artifacts_with_collapsed()
    |> Enum.map(fn artifact ->
      children = build_tree.(build_tree, artifact.id)
      Map.put(artifact, :children, children)
    end)
  end

  defp map_artifacts_with_collapsed(artifacts) do
    artifacts
    |> Enum.sort_by(&(-&1.size))
    |> Enum.with_index()
    |> Enum.map(fn {artifact, index} ->
      Map.put(artifact, :collapsed?, index >= 50)
    end)
  end

  def install_size_deviation(%Bundle{} = bundle) do
    project = Repo.preload(bundle, :project).project
    last_bundle = last_project_bundle(project, git_branch: project.default_branch, bundle: bundle)

    if is_nil(last_bundle) do
      0.0
    else
      bundle.install_size / last_bundle.install_size - 1
    end
  end

  def distinct_project_app_bundles(%Project{} = project) do
    # ClickHouse runs `DISTINCT` before `ORDER BY`, so the
    # PostgreSQL-style `distinct(b.name) |> order_by(desc: inserted_at)`
    # pattern would deduplicate against an unordered scan and pick an
    # arbitrary row per name. Fetch the rows ordered by `inserted_at`
    # first and dedup in Elixir, which keeps the first (newest)
    # occurrence per name. Bounded by "one project's bundles in the
    # last 365 days" so the result set stays small in practice.
    from(b in Bundle)
    |> where([b], b.project_id == ^project.id)
    |> where([b], b.inserted_at > ^DateTime.add(DateTime.utc_now(), -365, :day))
    |> order_by([b], desc: b.inserted_at)
    |> ClickHouseRepo.all()
    |> decode_bundles()
    |> Enum.uniq_by(& &1.name)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def last_project_bundle(%Project{} = project, opts \\ []) do
    query = where(from(b in Bundle), [b], b.project_id == ^project.id)

    bundle = Keyword.get(opts, :bundle)

    query =
      if is_nil(bundle) do
        query
      else
        where(
          query,
          [b],
          b.id != type(^bundle.id, Ecto.UUID) and b.app_bundle_id == ^bundle.app_bundle_id and
            b.inserted_at < ^bundle.inserted_at
        )
      end

    name = Keyword.get(opts, :name)

    query =
      if is_nil(name) do
        query
      else
        where(query, [b], b.name == ^name)
      end

    inserted_before = Keyword.get(opts, :inserted_before)

    query =
      if is_nil(inserted_before) do
        query
      else
        where(query, [b], b.inserted_at < ^inserted_before)
      end

    period = Keyword.get(opts, :period)

    query =
      case period do
        {from, to} -> where(query, [b], b.inserted_at >= ^from and b.inserted_at <= ^to)
        _ -> query
      end

    git_branch = Keyword.get(opts, :git_branch)
    type = Keyword.get(opts, :type)

    fallback = Keyword.get(opts, :fallback, true)

    last_bundle =
      query
      |> then(&if(is_nil(git_branch), do: &1, else: where(&1, [b], b.git_branch == ^git_branch)))
      |> then(&if(is_nil(type), do: &1, else: where(&1, [b], b.type == ^Atom.to_string(type))))
      |> order_by([b], desc: b.inserted_at)
      |> limit(1)
      |> ClickHouseRepo.one()
      |> decode_bundle()

    if is_nil(last_bundle) && fallback do
      query
      |> then(&if(is_nil(type), do: &1, else: where(&1, [b], b.type == ^Atom.to_string(type))))
      |> order_by([b], desc: b.inserted_at)
      |> limit(1)
      |> ClickHouseRepo.one()
      |> decode_bundle()
    else
      last_bundle
    end
  end

  def list_bundles(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    {bundles, meta} = ClickHouseFlop.validate_and_run!(Bundle, attrs, for: Bundle)
    bundles = bundles |> decode_bundles() |> Repo.preload(preload)
    {bundles, meta}
  end

  def project_bundle_install_size_analytics(%Project{} = project, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    # Group bundles by date
    bundle_install_sizes =
      project
      |> project_bundles_by_date(opts)
      |> Enum.map(fn {date, bundles} ->
        # Find the latest bundle for each day
        latest_bundle =
          bundles
          |> Enum.sort_by(fn bundle -> bundle.inserted_at end, {:desc, DateTime})
          |> List.first()

        # Return analytics data point
        %{
          date: date,
          install_size: latest_bundle.install_size,
          bundle_id: latest_bundle.id
        }
      end)
      |> Enum.sort_by(fn %{date: date} -> date end)
      |> Map.new(fn %{date: date, install_size: install_size} -> {date, install_size} end)

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      average = Map.get(bundle_install_sizes, date)

      %{
        date: date,
        bundle_install_size:
          if is_nil(average) do
            find_fallback_size(bundle_install_sizes, date)
          else
            average
          end
      }
    end)
  end

  defp find_fallback_size(bundle_sizes, date) do
    1..7
    |> Enum.map(fn days_back ->
      previous_date = Date.add(date, -days_back)
      Map.get(bundle_sizes, previous_date)
    end)
    |> Enum.find(&(not is_nil(&1))) || 0
  end

  def bundle_download_size_analytics(%Project{} = project, opts \\ []) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    # Group bundles by date
    bundle_download_sizes =
      project
      |> project_bundles_by_date(opts)
      |> Enum.map(fn {date, bundles} ->
        # Find the latest bundle for each day
        latest_bundle =
          bundles
          |> Enum.sort_by(fn bundle -> bundle.inserted_at end, {:desc, DateTime})
          |> List.first()

        # Return analytics data point
        %{
          date: date,
          download_size: latest_bundle.download_size,
          bundle_id: latest_bundle.id
        }
      end)
      |> Enum.sort_by(fn %{date: date} -> date end)
      |> Map.new(fn %{date: date, download_size: download_size} -> {date, download_size} end)

    date_period
    |> date_range_for_date_period(start_datetime: start_datetime, end_datetime: end_datetime)
    |> Enum.map(fn date ->
      average = Map.get(bundle_download_sizes, date)

      %{
        date: date,
        bundle_download_size:
          if is_nil(average) do
            find_fallback_size(bundle_download_sizes, date)
          else
            average
          end
      }
    end)
  end

  defp project_bundles_by_date(%Project{} = project, opts) do
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(DateTime.utc_now(), -30, :day))
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    git_branch = Keyword.get(opts, :git_branch)
    type = Keyword.get(opts, :type)
    name = Keyword.get(opts, :name)
    date_period = date_period(start_datetime: start_datetime, end_datetime: end_datetime)

    query =
      from(b in Bundle)
      |> where([b], b.project_id == ^project.id)
      |> where([b], b.inserted_at >= ^start_datetime and b.inserted_at <= ^end_datetime)
      |> then(&if(is_nil(git_branch), do: &1, else: where(&1, [b], b.git_branch == ^git_branch)))
      |> then(&if(is_nil(type), do: &1, else: where(&1, [b], b.type == ^Atom.to_string(type))))
      |> then(&if(is_nil(name), do: &1, else: where(&1, [b], b.name == ^name)))
      |> select([b], %{
        id: b.id,
        inserted_at: b.inserted_at,
        install_size: b.install_size,
        download_size: b.download_size
      })

    query
    |> ClickHouseRepo.all()
    |> Enum.map(fn bundle ->
      inserted_at = from_naive_usec(bundle.inserted_at)
      bundle = %{bundle | inserted_at: inserted_at}

      date =
        case date_period do
          :hour -> bundle.inserted_at |> DateTime.truncate(:second) |> truncate_to_hour()
          :day -> DateTime.to_date(bundle.inserted_at)
          :month -> bundle.inserted_at |> DateTime.to_date() |> Timex.beginning_of_month()
        end

      Map.put(bundle, :date, date)
    end)
    |> Enum.group_by(fn bundle -> bundle.date end)
  end

  defp truncate_to_hour(%DateTime{} = dt) do
    %{dt | minute: 0, second: 0, microsecond: {0, 0}}
  end

  defp date_period(opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)
    days_delta = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    cond do
      days_delta <= 1 -> :hour
      days_delta >= 60 -> :month
      true -> :day
    end
  end

  defp date_range_for_date_period(:hour, opts) do
    start_datetime = DateTime.truncate(Keyword.get(opts, :start_datetime), :second)
    end_datetime = DateTime.truncate(Keyword.get(opts, :end_datetime), :second)

    start_datetime
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, end_datetime) != :gt))
  end

  defp date_range_for_date_period(date_period, opts) do
    start_datetime = Keyword.get(opts, :start_datetime)
    end_datetime = Keyword.get(opts, :end_datetime)
    start_date = DateTime.to_date(start_datetime)
    end_date = DateTime.to_date(end_datetime)

    start_date
    |> Date.range(end_date)
    |> Enum.filter(fn date ->
      case date_period do
        :month ->
          date.day == 1

        :day ->
          true
      end
    end)
  end

  def default_app(%Project{} = project) do
    apps = distinct_project_app_bundles(project)

    if Enum.empty?(apps) do
      nil
    else
      (Enum.find(apps, &Enum.member?(&1.supported_platforms, :ios)) ||
         List.first(apps)).name
    end
  end

  def has_bundles_in_project_default_branch?(%Project{} = project, opts \\ []) do
    name = Keyword.get(opts, :name)

    from(b in Bundle)
    |> where([b], b.project_id == ^project.id)
    |> where([b], b.git_branch == ^project.default_branch)
    |> then(&if(is_nil(name), do: &1, else: where(&1, [b], b.name == ^name)))
    |> limit(1)
    |> ClickHouseRepo.exists?()
  end

  def has_bundles_in_project?(%Project{} = project) do
    from(b in Bundle)
    |> where([b], b.project_id == ^project.id)
    |> limit(1)
    |> ClickHouseRepo.exists?()
  end

  def delete_bundle!(%Bundle{} = bundle) do
    # ClickHouse mutations are async by default; force `mutations_sync = 1`
    # so the row is gone by the time the call returns and follow-up reads
    # (including the dashboard redirect) cannot observe it.
    IngestRepo.query!(
      "ALTER TABLE bundles DELETE WHERE id = {bundle_id:UUID} SETTINGS mutations_sync = 1",
      %{"bundle_id" => bundle.id}
    )

    IngestRepo.query!(
      "ALTER TABLE artifacts DELETE WHERE bundle_id = {bundle_id:UUID} SETTINGS mutations_sync = 1",
      %{"bundle_id" => bundle.id}
    )

    :ok
  end

  def get_project_bundle_thresholds(%Project{} = project) do
    Repo.all(from(bt in BundleThreshold, where: bt.project_id == ^project.id, order_by: [asc: bt.inserted_at]))
  end

  def get_bundle_threshold(id) do
    case Repo.get(BundleThreshold, id) do
      nil -> {:error, :not_found}
      threshold -> {:ok, threshold}
    end
  end

  def create_bundle_threshold(attrs) do
    %BundleThreshold{id: UUIDv7.generate()}
    |> BundleThreshold.changeset(attrs)
    |> Repo.insert()
  end

  def update_bundle_threshold(%BundleThreshold{} = threshold, attrs) do
    threshold
    |> BundleThreshold.changeset(attrs)
    |> Repo.update()
  end

  def delete_bundle_threshold(%BundleThreshold{} = threshold) do
    Repo.delete(threshold)
  end

  def evaluate_project_thresholds(%Project{} = project, %Bundle{} = bundle) do
    thresholds = get_project_bundle_thresholds(project)

    Enum.reduce_while(thresholds, :ok, fn threshold, :ok ->
      case evaluate_single_threshold(project, bundle, threshold) do
        :ok -> {:cont, :ok}
        {:violated, _, _} = violation -> {:halt, violation}
      end
    end)
  end

  defp evaluate_single_threshold(project, bundle, threshold) do
    if threshold.bundle_name && threshold.bundle_name != bundle.name do
      :ok
    else
      baseline =
        last_project_bundle(project,
          git_branch: threshold.baseline_branch,
          name: bundle.name,
          fallback: false
        )

      check_threshold_deviation(threshold, bundle, baseline)
    end
  end

  defp check_threshold_deviation(_threshold, _bundle, nil), do: :ok

  defp check_threshold_deviation(threshold, bundle, baseline) do
    {current_size, baseline_size} =
      case threshold.metric do
        :install_size -> {bundle.install_size, baseline.install_size}
        :download_size -> {bundle.download_size, baseline.download_size}
      end

    if is_nil(current_size) || is_nil(baseline_size) || baseline_size == 0 do
      :ok
    else
      deviation = (current_size - baseline_size) / baseline_size * 100

      if deviation > threshold.deviation_percentage do
        {:violated, threshold, %{current_size: current_size, baseline_size: baseline_size, deviation: deviation}}
      else
        :ok
      end
    end
  end

  defp flatten_artifacts(artifacts, bundle_id, parent_id, current_timestamp) do
    valid_artifact_types = Enum.map(Artifact.artifact_types(), &Atom.to_string/1)

    Enum.flat_map(artifacts, fn artifact ->
      artifact_id = UUIDv7.generate()
      artifact_type = Atom.to_string(Map.fetch!(artifact, :artifact_type))

      if !Enum.member?(valid_artifact_types, artifact_type) do
        raise "Invalid artifact type: #{artifact_type}. Must be one of #{inspect(valid_artifact_types)}."
      end

      current_artifact = %{
        id: artifact_id,
        artifact_type: artifact_type,
        path: Map.get(artifact, :path),
        size: Map.get(artifact, :size),
        shasum: Map.get(artifact, :shasum),
        bundle_id: bundle_id,
        artifact_id: parent_id,
        inserted_at: current_timestamp,
        updated_at: current_timestamp
      }

      children = Map.get(artifact, :children) || []
      child_artifacts = flatten_artifacts(children, bundle_id, artifact_id, current_timestamp)

      [current_artifact | child_artifacts]
    end)
  end
end
