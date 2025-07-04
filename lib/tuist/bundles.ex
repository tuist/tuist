defmodule Tuist.Bundles do
  @moduledoc """
  The Bundles context.
  """

  import Ecto.Query

  alias Tuist.Bundles.Artifact
  alias Tuist.Bundles.Bundle
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @doc """
  Creates a bundle with associated artifacts.
  """
  def create_bundle(attrs \\ %{}) do
    {artifacts, bundle_attrs} = Map.pop(attrs, :artifacts, [])
    bundle_id = Map.fetch!(attrs, :id)

    Ecto.Multi.new()
    |> create_bundle_multi(bundle_attrs)
    |> create_artifacts_multi(artifacts, bundle_id)
    |> execute_bundle_transaction()
  end

  defp create_bundle_multi(multi, bundle_attrs) do
    Ecto.Multi.insert(multi, :bundle, Bundle.changeset(%Bundle{}, bundle_attrs))
  end

  defp create_artifacts_multi(multi, artifacts, bundle_id) do
    Ecto.Multi.run(multi, :artifacts, fn repo, _changes ->
      insert_artifacts_in_batches(repo, artifacts, bundle_id)
    end)
  end

  defp execute_bundle_transaction(multi) do
    case Repo.transaction(multi) do
      {:ok, %{bundle: bundle}} -> {:ok, bundle}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
    end
  end

  defp insert_artifacts_in_batches(repo, artifacts, bundle_id) do
    artifacts
    |> flatten_artifacts(bundle_id)
    |> batch_insert_artifacts(repo)
  end

  defp batch_insert_artifacts(flattened_artifacts, repo) do
    # Each artifact has ~10 fields, so 6000 artifacts per batch keeps us under 65535 params
    batch_size = 6000

    flattened_artifacts
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      case repo.insert_all(Artifact, batch, returning: true) do
        {_count, artifacts} -> {:cont, {:ok, acc ++ artifacts}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Gets a single bundle.
  """
  def get_bundle(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])
    bundle = Bundle |> Repo.get(id) |> Repo.preload(preload)

    if is_nil(bundle) do
      {:error, :not_found}
    else
      {:ok, %{bundle | artifacts: bundle_artifacts(bundle)}}
    end
  end

  defp bundle_artifacts(%Bundle{id: id}) do
    # Get all artifacts for this bundle in a single query
    all_artifacts =
      Repo.all(
        from a in Artifact,
          where: a.bundle_id == ^id,
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
              id: Ecto.UUID.generate(),
              size: missing_size,
              path: parent.path <> "/Unknown",
              children: [],
              artifact_type: :unknown,
              shasum: Ecto.UUID.generate(),
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
    from(b in Bundle)
    |> where([b], b.project_id == ^project.id)
    |> where([b], b.inserted_at > ^DateTime.add(DateTime.utc_now(), -365, :day))
    |> order_by([b], desc: b.inserted_at)
    |> distinct([b], b.name)
    |> Repo.all()
    |> Enum.sort_by(fn bundle -> bundle.inserted_at end, {:desc, DateTime})
  end

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
          b.id != ^bundle.id and b.app_bundle_id == ^bundle.app_bundle_id and
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
        where(query, [b], b.inserted_at < ^DateTime.new!(inserted_before, ~T[00:00:00]))
      end

    git_branch = Keyword.get(opts, :git_branch)

    last_bundle =
      query
      |> then(&if(is_nil(git_branch), do: &1, else: where(&1, [b], b.git_branch == ^git_branch)))
      |> order_by([b], desc: b.inserted_at)
      |> limit(1)
      |> Repo.one()

    if is_nil(last_bundle) do
      query |> order_by([b], desc: b.inserted_at) |> limit(1) |> Repo.one()
    else
      last_bundle
    end
  end

  def list_bundles(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    Bundle
    |> preload(^preload)
    |> Flop.validate_and_run!(attrs, for: Bundle)
  end

  def project_bundle_install_size_analytics(%Project{} = project, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))
    date_period = date_period(start_date: start_date, end_date: end_date)
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
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
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
    |> Enum.filter(&(not is_nil(&1)))
    |> List.first() || 0
  end

  def bundle_download_size_analytics(%Project{} = project, opts \\ []) do
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))
    date_period = date_period(start_date: start_date, end_date: end_date)
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
    |> date_range_for_date_period(start_date: start_date, end_date: end_date)
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
    start_date = Keyword.get(opts, :start_date, Date.add(DateTime.utc_now(), -30))
    end_date = Keyword.get(opts, :end_date, DateTime.to_date(DateTime.utc_now()))
    git_branch = Keyword.get(opts, :git_branch)
    date_period = date_period(start_date: start_date, end_date: end_date)

    # Get all bundles for the project with date truncated to day
    query =
      from(b in Bundle)
      |> where([b], b.project_id == ^project.id)
      |> then(&if(is_nil(git_branch), do: &1, else: where(&1, [b], b.git_branch == ^git_branch)))
      |> select([b], %{
        id: b.id,
        date: fragment("DATE(?) as date", b.inserted_at),
        install_size: b.install_size,
        download_size: b.download_size,
        inserted_at: b.inserted_at
      })

    query
    |> Repo.all()
    |> Enum.map(fn bundle ->
      case date_period do
        :day -> bundle
        :month -> Map.put(bundle, :date, Timex.beginning_of_month(bundle.date))
      end
    end)
    |> Enum.group_by(fn bundle -> bundle.date end)
  end

  defp date_period(opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)
    days_delta = Date.diff(end_date, start_date)

    if days_delta >= 60 do
      :month
    else
      :day
    end
  end

  defp date_range_for_date_period(date_period, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

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

  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 1)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 1)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  def default_app(%Project{} = project) do
    apps = distinct_project_app_bundles(project)

    if Enum.empty?(apps) do
      nil
    else
      (apps |> Enum.filter(&Enum.member?(&1.supported_platforms, :ios)) |> List.first() ||
         List.first(apps)).name
    end
  end

  def has_bundles_in_project_default_branch?(%Project{} = project) do
    from(b in Bundle)
    |> where([b], b.project_id == ^project.id)
    |> where([b], b.git_branch == ^project.default_branch)
    |> limit(1)
    |> Repo.exists?()
  end

  def delete_bundle!(%Bundle{} = bundle) do
    Repo.delete!(bundle)
  end

  defp flatten_artifacts(
         artifacts,
         bundle_id,
         parent_id \\ nil,
         current_timestamp \\ DateTime.truncate(DateTime.utc_now(), :second)
       ) do
    valid_artifact_types =
      Artifact |> Ecto.Enum.values(:artifact_type) |> Enum.map(&Atom.to_string/1)

    Enum.flat_map(artifacts, fn artifact ->
      artifact_id = UUIDv7.generate()
      artifact_type = artifact["artifact_type"]

      if !Enum.member?(valid_artifact_types, artifact_type) do
        raise "Invalid artifact type: #{artifact_type}. Must be one of #{inspect(valid_artifact_types)}."
      end

      current_artifact = %{
        id: artifact_id,
        artifact_type: String.to_atom(artifact["artifact_type"]),
        path: artifact["path"],
        size: artifact["size"],
        shasum: artifact["shasum"],
        bundle_id: bundle_id,
        artifact_id: parent_id,
        inserted_at: current_timestamp,
        updated_at: current_timestamp
      }

      children = artifact["children"] || []
      child_artifacts = flatten_artifacts(children, bundle_id, artifact_id, current_timestamp)

      [current_artifact | child_artifacts]
    end)
  end
end
