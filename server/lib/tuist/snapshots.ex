defmodule Tuist.Snapshots do
  @moduledoc """
  Hosted visual snapshot testing: snapshot builds, their images, the baseline
  each build is compared with, and the review of what changed.

  A client (the Gradle plugin, later the CLI) records images with the
  project's snapshot library and uploads them as a build of a named **set**,
  such as `android-phone`. Images are content-addressed: the client sends
  every image's SHA-256 and uploads only the ones the project doesn't store
  yet, so a build on a commit that changed nothing uploads nothing.

  The **baseline** is found through Git, the way Sentry, Argos and Percy do
  it, instead of golden images kept in the repository. Candidates are the
  set's processed builds on the default branch, plus approved builds on other
  branches. In order:

  1. a candidate at the build's merge base with the base branch;
  2. the nearest candidate among the ancestors of the merge base (or of the
     build's own commit when there is none) in the commit graph clients
     upload (`Tuist.GitHistory`);
  3. the newest candidate on the default branch.

  A build on the default branch becomes a baseline once processed, so a
  change merged after review is the next build's reference without a
  separate promotion step.

  A run that renders only some images, such as one filtered to a few tests,
  is **selective**: the client sends the names of every image the suite
  renders (`all_image_names`, Sentry's `--all-image-file-names`) or marks
  the build `selective` (Sentry's `--selective`, every image it didn't
  upload counts). Those images are skipped rather than removed.

  The dashboard lists **commits** (`Tuist.Snapshots.Commit`), not builds: a
  commit pools its builds the way coverage pools a commit's runs, so sets,
  shards and reruns read as one. Within a set, each image is the latest
  build's that rendered it (`commit_images/2`), and a commit is complete once
  its CI sends the signal that also completes its coverage.
  """
  import Ecto.Query

  alias Tuist.GitHistory
  alias Tuist.Repo
  alias Tuist.Snapshots.Build
  alias Tuist.Snapshots.Commit
  alias Tuist.Snapshots.Diff
  alias Tuist.Snapshots.Image
  alias Tuist.Snapshots.Thumbnail
  alias Tuist.Snapshots.Workers.CheckRunWorker
  alias Tuist.Snapshots.Workers.ProcessBuildWorker
  alias Tuist.Storage

  require Logger

  @baseline_candidates_limit 200
  @max_images 25_000
  @hash_pattern ~r/^[0-9a-f]{64}$/

  def max_images, do: @max_images

  @doc """
  Creates a build with its images' manifest and returns it with the content
  hashes the client still has to upload, each with a presigned upload URL.
  """
  def create_build(project, attrs, images) do
    {all_image_names, attrs} = Map.pop(attrs, :all_image_names)

    with :ok <- validate_images(images),
         :ok <- validate_all_image_names(all_image_names) do
      uploaded = MapSet.new(images, & &1.name)
      skipped = Enum.reject(Enum.uniq(all_image_names || []), &MapSet.member?(uploaded, &1))

      fn ->
        build =
          %Build{}
          |> Build.create_changeset(Map.put(attrs, :project_id, project.id))
          |> Repo.insert()
          |> case do
            {:ok, build} -> build
            {:error, changeset} -> Repo.rollback(changeset)
          end

        now = DateTime.truncate(DateTime.utc_now(), :second)

        images
        |> Enum.map(fn image ->
          %{
            id: UUIDv7.generate(),
            build_id: build.id,
            name: image.name,
            content_hash: image.content_hash,
            width: Map.get(image, :width),
            height: Map.get(image, :height),
            test_identifier: Map.get(image, :test_identifier),
            display_name: Map.get(image, :display_name),
            group: Map.get(image, :group),
            tags: Map.get(image, :tags) || %{},
            diff_threshold: Map.get(image, :diff_threshold),
            inserted_at: now,
            updated_at: now
          }
        end)
        |> Enum.chunk_every(1_000)
        |> Enum.each(&Repo.insert_all(Image, &1))

        # Placeholders for the images the run didn't render; processing
        # replaces them with the baseline's or drops them.
        skipped
        |> Enum.map(
          &%{id: UUIDv7.generate(), build_id: build.id, name: &1, status: "skipped", inserted_at: now, updated_at: now}
        )
        |> Enum.chunk_every(1_000)
        |> Enum.each(&Repo.insert_all(Image, &1))

        build
      end
      |> Repo.transaction()
      |> case do
        {:ok, build} ->
          refresh_commit(project, build.git_commit_sha)
          hashes = images |> Enum.map(& &1.content_hash) |> Enum.uniq()
          missing = hashes -- stored_hashes(project, hashes, build.id)
          {:ok, build, missing}

        {:error, _} = error ->
          error
      end
    end
  end

  defp validate_images(images) do
    names = Enum.map(images, & &1.name)

    cond do
      length(images) > @max_images ->
        {:error, :too_many_images}

      length(Enum.uniq(names)) != length(names) ->
        {:error, :duplicate_image_names}

      Enum.any?(images, &(not Regex.match?(@hash_pattern, &1.content_hash))) ->
        {:error, :invalid_content_hash}

      Enum.any?(names, &(not valid_name?(&1))) ->
        {:error, :invalid_image_name}

      Enum.any?(images, &(not valid_metadata?(&1))) ->
        {:error, :invalid_image_metadata}

      true ->
        :ok
    end
  end

  defp validate_all_image_names(nil), do: :ok

  defp validate_all_image_names(names) when is_list(names) do
    cond do
      length(names) > @max_images -> {:error, :too_many_images}
      Enum.all?(names, &(is_binary(&1) and valid_name?(&1))) -> :ok
      true -> {:error, :invalid_image_name}
    end
  end

  defp validate_all_image_names(_names), do: {:error, :invalid_image_name}

  defp valid_metadata?(image) do
    valid_tags?(Map.get(image, :tags) || %{}) and valid_threshold?(Map.get(image, :diff_threshold)) and
      optional_string?(Map.get(image, :display_name), 512) and optional_string?(Map.get(image, :group), 255)
  end

  defp valid_tags?(tags) when is_map(tags) and map_size(tags) <= 50,
    do: Enum.all?(tags, fn {key, value} -> short_string?(to_string(key), 255) and short_string?(value, 255) end)

  defp valid_tags?(_tags), do: false

  defp valid_threshold?(nil), do: true
  defp valid_threshold?(threshold) when is_number(threshold), do: threshold >= 0 and threshold <= 1
  defp valid_threshold?(_threshold), do: false

  defp optional_string?(nil, _max), do: true
  defp optional_string?(value, max), do: short_string?(value, max)

  defp short_string?(value, max), do: is_binary(value) and String.length(value) <= max

  defp valid_name?(name) do
    byte_size(name) in 1..512 and not String.starts_with?(name, "/") and
      not Enum.member?(String.split(name, "/"), "..")
  end

  # The hashes another build of the project already uploaded. Only builds the
  # client completed count: an abandoned upload may never have put its images.
  defp stored_hashes(_project, [], _build_id), do: []

  defp stored_hashes(project, hashes, build_id) do
    Repo.all(
      from(i in Image,
        join: b in Build,
        on: b.id == i.build_id,
        where:
          b.project_id == ^project.id and b.id != ^build_id and b.state in ["processing", "processed"] and
            i.content_hash in ^hashes,
        distinct: true,
        select: i.content_hash
      )
    )
  end

  def upload_url(project, content_hash) do
    Storage.generate_upload_url(blob_key(project, content_hash), project.account, expires_in: 3600)
  end

  def download_url(project, content_hash) do
    Storage.generate_download_url(blob_key(project, content_hash), project.account, expires_in: 3600)
  end

  def blob_key(project, content_hash) do
    "#{String.downcase(project.account.name)}/#{String.downcase(project.name)}/snapshots/blobs/#{content_hash}.png"
  end

  defp thumbnail_key(project, content_hash) do
    "#{String.downcase(project.account.name)}/#{String.downcase(project.name)}/snapshots/thumbnails/#{content_hash}.webp"
  end

  # The library shows the default branch's images, so its builds store a
  # thumbnail of each image whose content their baseline didn't already
  # have; thumbnails are content-addressed like blobs, so each is rendered
  # once. A failure only costs the grid a full-size image.
  defp store_thumbnails(project, compared) do
    compared
    |> Enum.reject(fn {image, attrs} -> image.content_hash == attrs[:baseline_content_hash] end)
    |> Enum.map(fn {image, _attrs} -> image.content_hash end)
    |> Enum.uniq()
    |> Task.async_stream(&store_thumbnail(project, &1), max_concurrency: 8, timeout: 120_000, on_timeout: :kill_task)
    |> Stream.run()
  end

  defp store_thumbnail(project, content_hash) do
    with binary when is_binary(binary) <- Storage.get_object_as_string(blob_key(project, content_hash), project.account),
         {:ok, png} <- Thumbnail.render(binary) do
      Storage.put_object(thumbnail_key(project, content_hash), png, project.account)
    else
      error -> Logger.warning("Snapshot thumbnail #{content_hash} not stored: #{inspect(error)}")
    end
  end

  defp diff_key(project, build, image) do
    "#{String.downcase(project.account.name)}/#{String.downcase(project.name)}/snapshots/builds/#{build.id}/diffs/#{image.id}.png"
  end

  def get_build_by_id(id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         %Build{} = build <- Repo.get(Build, id) do
      {:ok, Repo.preload(build, project: :vcs_connection)}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_build(project, id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         %Build{} = build <- Repo.one(from(b in Build, where: b.id == ^id and b.project_id == ^project.id)) do
      {:ok,
       Repo.preload(build, [
         :baseline_build,
         :approved_from_build,
         approved_by_account: :user,
         rejected_by_account: :user
       ])}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The project's snapshot activity between `:start_datetime` and
  `:end_datetime`, bucketed by hour, day or month like the other dashboard
  charts: `:snapshot_runs` (builds uploaded: one per set, shard and rerun;
  an upload that never finished doesn't count), `:visual_changes` (commits,
  by their first upload, in which a snapshot changed or was removed compared
  with the baseline; new snapshots alone don't count) and `:snapshots`
  (images in the latest default-branch build of each set, summed over sets;
  `nil` in buckets before the default branch's first upload).
  Each has `count`, `trend` (percent against the previous period of the same
  length, or against the value at the start of the period for snapshots),
  `dates` and `values`.
  """
  def analytics(project, opts) do
    end_datetime = Keyword.get(opts, :end_datetime, DateTime.utc_now())
    start_datetime = Keyword.get(opts, :start_datetime, DateTime.add(end_datetime, -30, :day))
    period = analytics_period(start_datetime, end_datetime)
    dates = analytics_dates(period, start_datetime, end_datetime)
    previous_start = DateTime.add(start_datetime, -DateTime.diff(end_datetime, start_datetime), :second)

    runs = runs_by_bucket(project, period, start_datetime, end_datetime)
    previous_runs = runs_by_bucket(project, period, previous_start, start_datetime)
    changes = changes_by_bucket(project, period, start_datetime, end_datetime)
    previous_changes = changes_by_bucket(project, period, previous_start, start_datetime)

    snapshots = tracked_snapshots(project, period, dates, start_datetime, end_datetime)
    snapshots_start = tracked_snapshots_at(project, start_datetime)
    snapshots_count = List.last(snapshots) || snapshots_start

    %{
      snapshot_runs: bucketed(runs, previous_runs, dates),
      visual_changes: bucketed(changes, previous_changes, dates),
      snapshots: %{
        count: snapshots_count,
        trend: trend(snapshots_start, snapshots_count),
        dates: dates,
        values: snapshots
      }
    }
  end

  defp bucketed(counts, previous_counts, dates) do
    count = counts |> Map.values() |> Enum.sum()

    %{
      count: count,
      trend: previous_counts |> Map.values() |> Enum.sum() |> trend(count),
      dates: dates,
      values: Enum.map(dates, &Map.get(counts, &1, 0))
    }
  end

  defp analytics_period(start_datetime, end_datetime) do
    days = Date.diff(DateTime.to_date(end_datetime), DateTime.to_date(start_datetime))

    cond do
      days <= 1 -> :hour
      days >= 60 -> :month
      true -> :day
    end
  end

  defp analytics_dates(:hour, start_datetime, end_datetime) do
    %{start_datetime | minute: 0, second: 0, microsecond: {0, 0}}
    |> Stream.iterate(&DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, end_datetime) != :gt))
    |> Enum.map(&Calendar.strftime(&1, "%Y-%m-%d %H:00"))
  end

  defp analytics_dates(:month, start_datetime, end_datetime) do
    start_datetime
    |> DateTime.to_date()
    |> Date.beginning_of_month()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.filter(&(&1.day == 1))
    |> Enum.map(&Date.to_iso8601/1)
  end

  defp analytics_dates(:day, start_datetime, end_datetime) do
    start_datetime
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(end_datetime))
    |> Enum.map(&Date.to_iso8601/1)
  end

  defp bucket_key(:hour, %DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:00")
  defp bucket_key(:day, %DateTime{} = datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()

  defp bucket_key(:month, %DateTime{} = datetime),
    do: datetime |> DateTime.to_date() |> Date.beginning_of_month() |> Date.to_iso8601()

  defp runs_by_bucket(project, period, start_datetime, end_datetime) do
    from(b in Build,
      where:
        b.project_id == ^project.id and b.state != "uploading" and b.inserted_at >= ^start_datetime and
          b.inserted_at <= ^end_datetime,
      select: b.inserted_at
    )
    |> Repo.all()
    |> Enum.frequencies_by(&bucket_key(period, &1))
  end

  defp changes_by_bucket(project, period, start_datetime, end_datetime) do
    from(c in Commit,
      where:
        c.project_id == ^project.id and c.runs_count > 0 and c.changed_count + c.removed_count > 0 and
          c.inserted_at >= ^start_datetime and c.inserted_at <= ^end_datetime,
      select: c.inserted_at
    )
    |> Repo.all()
    |> Enum.frequencies_by(&bucket_key(period, &1))
  end

  defp default_branch_totals_query(project) do
    from(b in Build,
      where: b.project_id == ^project.id and b.state == "processed" and b.git_branch == ^project.default_branch,
      select:
        {b.inserted_at, b.id, b.set_name,
         b.unchanged_count + b.changed_count + b.added_count + b.renamed_count + b.skipped_count}
    )
  end

  defp tracked_snapshots_at(project, datetime) do
    project
    |> default_branch_totals_query()
    |> where([b], b.inserted_at < ^datetime)
    |> Repo.all()
    |> latest_total_per_set(%{})
    |> Map.values()
    |> Enum.sum()
  end

  defp tracked_snapshots(project, period, dates, start_datetime, end_datetime) do
    initial =
      project
      |> default_branch_totals_query()
      |> where([b], b.inserted_at < ^start_datetime)
      |> Repo.all()
      |> latest_total_per_set(%{})

    by_bucket =
      project
      |> default_branch_totals_query()
      |> where([b], b.inserted_at >= ^start_datetime and b.inserted_at <= ^end_datetime)
      |> Repo.all()
      |> Enum.group_by(&bucket_key(period, elem(&1, 0)))

    # Before the default branch's first upload the suite's size is unknown, not zero.
    dates
    |> Enum.map_reduce(initial, fn date, totals ->
      totals = latest_total_per_set(Map.get(by_bucket, date, []), totals)
      {if(totals == %{}, do: nil, else: totals |> Map.values() |> Enum.sum()), totals}
    end)
    |> elem(0)
  end

  # Timestamps are to the second, so builds uploaded in the same second are
  # ordered by their time-ordered UUIDv7 ids.
  defp latest_total_per_set(rows, totals) do
    rows
    |> Enum.sort_by(fn {inserted_at, id, _set_name, _total} -> {DateTime.to_unix(inserted_at), id} end)
    |> Enum.reduce(totals, fn {_inserted_at, _id, set_name, total}, acc -> Map.put(acc, set_name, total) end)
  end

  defp trend(0, _current), do: 0.0
  defp trend(previous, current), do: (current - previous) / previous * 100

  @status_order %{"changed" => 0, "removed" => 1, "added" => 2, "renamed" => 3, "skipped" => 4, "unchanged" => 5}

  def list_images(%Build{id: build_id}) do
    from(i in Image, where: i.build_id == ^build_id)
    |> Repo.all()
    |> Enum.sort_by(&{Map.get(@status_order, &1.status, 4), &1.name})
  end

  def get_image(%Build{id: build_id}, image_id) do
    with {:ok, _} <- Ecto.UUID.cast(image_id),
         %Image{} = image <- Repo.one(from(i in Image, where: i.id == ^image_id and i.build_id == ^build_id)) do
      {:ok, image}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  The client finished uploading: checks that every image is stored and
  queues the comparison.
  """
  def complete_build(project, %Build{state: "uploading"} = build) do
    hashes =
      Repo.all(
        from(i in Image,
          where: i.build_id == ^build.id and not is_nil(i.content_hash),
          distinct: true,
          select: i.content_hash
        )
      )

    missing =
      (hashes -- stored_hashes(project, hashes, build.id))
      |> Task.async_stream(&{&1, Storage.object_exists?(blob_key(project, &1), project.account)},
        max_concurrency: 20,
        timeout: 30_000
      )
      |> Enum.flat_map(fn
        {:ok, {_hash, true}} -> []
        {:ok, {hash, false}} -> [hash]
      end)

    if missing == [] do
      with {:ok, build} <-
             Repo.transaction(fn ->
               {:ok, build} = build |> Build.state_changeset(%{state: "processing"}) |> Repo.update()
               {:ok, _job} = %{build_id: build.id} |> ProcessBuildWorker.new() |> Oban.insert()
               build
             end) do
        refresh_commit(project, build.git_commit_sha)
        {:ok, build}
      end
    else
      {:error, {:missing_images, missing}}
    end
  end

  def complete_build(_project, %Build{} = build), do: {:ok, build}

  @doc """
  The build's review status: `processing`, `failed`, `baseline` (a build on
  the default branch, which later builds compare with and nobody reviews),
  `approved`, `rejected`, `passed` (nothing changed or was removed compared
  with the baseline; new, renamed and skipped snapshots need no review), or
  `needs_review`.
  """
  def status(%Build{state: state}, _project) when state in ["uploading", "processing"], do: "processing"
  def status(%Build{state: "failed"}, _project), do: "failed"
  def status(%Build{rejected_at: %DateTime{}}, _project), do: "rejected"
  def status(%Build{approved_at: %DateTime{}}, _project), do: "approved"

  def status(%Build{} = build, project) do
    cond do
      default_branch?(build, project) -> "baseline"
      build.changed_count + build.removed_count == 0 -> "passed"
      true -> "needs_review"
    end
  end

  defp default_branch?(build, project), do: not is_nil(build.git_branch) and build.git_branch == project.default_branch

  @doc """
  Whether the build has changes someone can approve or reject: a processed
  build off the default branch in which images changed or were removed.
  A review can be changed: approving a rejected build, or rejecting an
  approved one, replaces the earlier review.
  """
  def reviewable?(%Build{state: "processed"} = build, project),
    do: not default_branch?(build, project) and build.changed_count + build.removed_count > 0

  def reviewable?(%Build{}, _project), do: false

  @doc """
  Approves a build's changes, as a Tuist account from the review page or as
  a GitHub user (`github_handle:`) from the check run's Approve button, and
  updates the check run.
  """
  def approve_build(build, reviewer), do: review_build(build, reviewer, :approved)

  @doc """
  Rejects a build's changes, like `approve_build/2`: the build stays failed
  until someone approves it, or a later build no longer has those changes.
  """
  def reject_build(build, reviewer), do: review_build(build, reviewer, :rejected)

  defp review_build(%Build{} = build, reviewer, verdict) do
    build = Repo.preload(build, :project)

    reviewer_attrs =
      case reviewer do
        [github_handle: handle] -> %{"#{verdict}_by_github_handle": handle}
        account -> %{"#{verdict}_by_account_id": account.id}
      end

    if reviewable?(build, build.project) do
      with {:ok, build} <-
             build
             |> Build.review_changeset(
               Map.put(reviewer_attrs, :"#{verdict}_at", DateTime.truncate(DateTime.utc_now(), :second))
             )
             |> Repo.update() do
        enqueue_check_run(build)
        refresh_commit(build.project, build.git_commit_sha)
        {:ok, build}
      end
    else
      {:error, :not_reviewable}
    end
  end

  defp enqueue_check_run(build), do: %{build_id: build.id} |> CheckRunWorker.new() |> Oban.insert!()

  @doc """
  Compares a build with its baseline: unchanged images are those with the
  same content hash, changed ones are diffed pixel by pixel.
  """
  def process_build(%Build{} = build) do
    build = Repo.preload(build, project: :account)
    project = build.project
    baseline = resolve_baseline(build)

    {placeholders, images} =
      from(i in Image, where: i.build_id == ^build.id)
      |> Repo.all()
      |> Enum.split_with(&(&1.status == "skipped" and is_nil(&1.content_hash)))

    baseline_images =
      if baseline,
        do:
          Map.new(Repo.all(from(i in Image, where: i.build_id == ^baseline.id and i.status != "removed")), &{&1.name, &1}),
        else: %{}

    compared =
      images
      |> Task.async_stream(&compare_image(project, build, &1, Map.get(baseline_images, &1.name)),
        max_concurrency: 8,
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    names = MapSet.new(images, & &1.name)
    not_rendered = MapSet.new(placeholders, & &1.name)

    {skipped, missing} =
      baseline_images
      |> Map.values()
      |> Enum.reject(&MapSet.member?(names, &1.name))
      |> Enum.split_with(&(build.selective or MapSet.member?(not_rendered, &1.name)))

    {compared, removed} = detect_renames(compared, missing)

    if build.git_branch == project.default_branch, do: store_thumbnails(project, compared)

    now = DateTime.truncate(DateTime.utc_now(), :second)

    fn ->
      Enum.each(compared, fn {image, attrs} -> image |> Image.comparison_changeset(attrs) |> Repo.update!() end)

      Repo.delete_all(from(i in Image, where: i.id in ^Enum.map(placeholders, & &1.id)))

      skipped
      |> Enum.map(fn image ->
        %{
          id: UUIDv7.generate(),
          build_id: build.id,
          name: image.name,
          content_hash: image.content_hash,
          width: image.width,
          height: image.height,
          test_identifier: image.test_identifier,
          display_name: image.display_name,
          group: image.group,
          tags: image.tags,
          diff_threshold: image.diff_threshold,
          status: "skipped",
          baseline_content_hash: image.content_hash,
          baseline_width: image.width,
          baseline_height: image.height,
          inserted_at: now,
          updated_at: now
        }
      end)
      |> Enum.chunk_every(1_000)
      |> Enum.each(&Repo.insert_all(Image, &1))

      removed
      |> Enum.map(fn image ->
        %{
          id: UUIDv7.generate(),
          build_id: build.id,
          name: image.name,
          test_identifier: image.test_identifier,
          status: "removed",
          # A removed image is reviewed under the name, group, and tags it had in the baseline.
          display_name: image.display_name,
          group: image.group,
          tags: image.tags,
          baseline_content_hash: image.content_hash,
          baseline_width: image.width,
          baseline_height: image.height,
          inserted_at: now,
          updated_at: now
        }
      end)
      |> Enum.chunk_every(1_000)
      |> Enum.each(&Repo.insert_all(Image, &1))

      counts = Enum.frequencies_by(compared, fn {_image, attrs} -> attrs.status end)

      build =
        build
        |> Build.state_changeset(%{
          state: "processed",
          baseline_build_id: baseline && baseline.id,
          unchanged_count: Map.get(counts, "unchanged", 0),
          changed_count: Map.get(counts, "changed", 0),
          added_count: Map.get(counts, "added", 0),
          removed_count: length(removed),
          renamed_count: Map.get(counts, "renamed", 0),
          skipped_count: length(skipped),
          processed_at: now,
          changes_signature: changes_signature(compared, removed)
        })
        |> Repo.update!()

      build = inherit_approval(build, project)
      enqueue_check_run(build)
      build
    end
    |> Repo.transaction()
    |> tap(fn {:ok, build} -> refresh_commit(project, build.git_commit_sha) end)
  end

  # An image that was removed and an added one with exactly its content are a
  # rename, as Sentry matches them: each removed image pairs with at most one
  # added image, in name order so the pairing is stable.
  defp detect_renames(compared, missing) do
    {renames, removed, _added} =
      missing
      |> Enum.sort_by(& &1.name)
      |> Enum.reduce({%{}, [], added_by_hash(compared)}, fn baseline, {renames, removed, added} ->
        case Map.get(added, baseline.content_hash, []) do
          [image | rest] -> {Map.put(renames, image.id, baseline), removed, Map.put(added, baseline.content_hash, rest)}
          [] -> {renames, [baseline | removed], added}
        end
      end)

    compared =
      Enum.map(compared, fn {image, attrs} ->
        case Map.get(renames, image.id) do
          nil ->
            {image, attrs}

          baseline ->
            {image,
             %{
               status: "renamed",
               renamed_from: baseline.name,
               baseline_content_hash: baseline.content_hash,
               baseline_width: baseline.width,
               baseline_height: baseline.height
             }}
        end
      end)

    {compared, Enum.reverse(removed)}
  end

  defp added_by_hash(compared) do
    compared
    |> Enum.filter(fn {_image, attrs} -> attrs.status == "added" end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort_by(& &1.name)
    |> Enum.group_by(& &1.content_hash)
  end

  # What a reviewer approves: each changed image's name with its baseline and
  # new content, and each removed image's name with its baseline content.
  # Unchanged and new images need no review, so they don't take part.
  defp changes_signature(compared, removed) do
    changed =
      for {image, %{status: "changed"} = attrs} <- compared,
          do: [image.name, "changed", attrs.baseline_content_hash, image.content_hash]

    removed = Enum.map(removed, &[&1.name, "removed", &1.content_hash, ""])

    case changed ++ removed do
      [] ->
        nil

      entries ->
        entries
        |> Enum.sort()
        |> Enum.map_join("\n", &Enum.join(&1, "\0"))
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)
    end
  end

  # A build that needs review is approved when an earlier build of its set on
  # the same branch with exactly the same changes was, as Sentry does: pushing
  # a commit that doesn't touch the reviewed images, or re-running CI, keeps
  # the approval. Any other difference (another image changed, or a changed
  # image changed again) needs a new review.
  defp inherit_approval(build, project) do
    with "needs_review" <- status(build, project),
         %Build{} = approved <-
           Repo.one(
             from(b in Build,
               where:
                 b.project_id == ^build.project_id and b.set_name == ^build.set_name and
                   b.git_branch == ^build.git_branch and b.changes_signature == ^build.changes_signature and
                   b.id != ^build.id and not is_nil(b.approved_at),
               order_by: [desc: b.approved_at],
               limit: 1
             )
           ) do
      build
      |> Build.review_changeset(%{
        approved_at: DateTime.truncate(DateTime.utc_now(), :second),
        approved_by_account_id: approved.approved_by_account_id,
        approved_by_github_handle: approved.approved_by_github_handle,
        approved_from_build_id: approved.approved_from_build_id || approved.id
      })
      |> Repo.update!()
    else
      _ -> build
    end
  end

  @doc """
  The comparison of `build` is still running: `ProcessBuildWorker` calls it
  as a heartbeat, which `recover_stalled_builds/1` reads.
  """
  def touch_processing(%Build{id: id}) do
    Repo.update_all(from(b in Build, where: b.id == ^id and b.state == "processing"),
      set: [updated_at: DateTime.truncate(DateTime.utc_now(), :second)]
    )

    :ok
  rescue
    error ->
      Logger.warning("Snapshot build #{id} heartbeat not recorded: #{inspect(error)}")
      :ok
  end

  @doc """
  Comparisons whose job Oban still records as executing but whose heartbeat
  stopped, because the pod running it went away: each is put back in the
  queue, or, when it used its last attempt, discarded with its build marked
  failed. Oban's Lifeline would only rescue them after 30 minutes, long after
  the client stopped waiting for a verdict.
  """
  def recover_stalled_builds(now \\ DateTime.utc_now()) do
    cutoff = now |> DateTime.add(-stalled_after_seconds(), :second) |> DateTime.truncate(:second)
    worker = inspect(ProcessBuildWorker)

    stalled =
      Repo.all(
        from(j in Oban.Job,
          join: b in Build,
          on: fragment("? ->> 'build_id'", j.args) == fragment("?::text", b.id),
          where:
            j.worker == ^worker and j.state == "executing" and j.attempted_at < ^cutoff and
              b.state == "processing" and b.updated_at < ^cutoff,
          select: {j, b}
        )
      )

    Enum.each(stalled, fn {job, build} -> recover_stalled_build(job, build, now) end)
    length(stalled)
  end

  # Two minutes: three missed beats, plus room for a slow write.
  defp stalled_after_seconds, do: div(ProcessBuildWorker.heartbeat_interval(), 1000) * 4

  defp recover_stalled_build(job, build, now) do
    executing = from(j in Oban.Job, where: j.id == ^job.id and j.state == "executing")

    if job.attempt < job.max_attempts do
      Logger.warning("Requeuing the stalled comparison of snapshot build #{build.id}")
      Repo.update_all(executing, set: [state: "available", scheduled_at: now])
    else
      Logger.warning("Failing snapshot build #{build.id}: its last comparison attempt stalled")

      {count, _} = Repo.update_all(executing, set: [state: "discarded", discarded_at: now])
      if count == 1, do: mark_failed(build)
    end
  end

  def mark_failed(%Build{} = build) do
    with {:ok, build} <- build |> Build.state_changeset(%{state: "failed"}) |> Repo.update() do
      refresh_commit(Repo.preload(build, :project).project, build.git_commit_sha)
      {:ok, build}
    end
  end

  defp compare_image(_project, _build, image, nil), do: {image, %{status: "added"}}

  defp compare_image(_project, _build, %Image{content_hash: hash} = image, %Image{content_hash: hash} = baseline) do
    {image,
     %{status: "unchanged", baseline_content_hash: hash, baseline_width: baseline.width, baseline_height: baseline.height}}
  end

  defp compare_image(project, build, image, baseline) do
    attrs = %{
      status: "changed",
      baseline_content_hash: baseline.content_hash,
      baseline_width: baseline.width,
      baseline_height: baseline.height
    }

    head_binary = Storage.get_object_as_string(blob_key(project, image.content_hash), project.account)
    baseline_binary = Storage.get_object_as_string(blob_key(project, baseline.content_hash), project.account)

    case Diff.compare(head_binary, baseline_binary) do
      # Different bytes can decode to the same pixels (another PNG encoder,
      # metadata): the image didn't change.
      {:ok, %{ratio: +0.0}} ->
        {image, %{attrs | status: "unchanged"}}

      # Within the image's threshold the difference is kept for the review
      # page, but the image doesn't count as changed.
      {:ok, %{ratio: ratio, diff_png: diff_png}} ->
        key = diff_key(project, build, image)
        :ok = Storage.put_object(key, diff_png, project.account)
        status = if ratio > (image.diff_threshold || 0.0), do: "changed", else: "unchanged"
        {image, Map.merge(attrs, %{status: status, diff_ratio: ratio, diff_key: key})}
    end
  end

  @doc """
  The build a build of `set` uploaded now from this checkout would be
  compared with, so a client can verify its images against it locally
  (`tuist snapshots download`). Nil when the set has no baseline yet.
  """
  def checkout_baseline(project, %{set: set, git_commit_sha: sha} = checkout) do
    resolve_baseline(%Build{
      # Matches no candidate: the build doesn't exist.
      id: UUIDv7.generate(),
      project_id: project.id,
      project: project,
      set_name: set,
      git_commit_sha: sha,
      merge_base_sha: Map.get(checkout, :merge_base_sha),
      git_remote_url_origin: Map.get(checkout, :git_remote_url_origin),
      inserted_at: DateTime.utc_now()
    })
  end

  @doc "The images a build holds, removed ones aside, by name."
  def build_images(%Build{} = build) do
    Repo.all(
      from(i in Image,
        where: i.build_id == ^build.id and (is_nil(i.status) or i.status != "removed") and not is_nil(i.content_hash),
        order_by: i.name
      )
    )
  end

  @doc """
  The build this one is compared with, or nil for the set's first build. See
  the module documentation for the order candidates are tried in.
  """
  def resolve_baseline(%Build{} = build) do
    build = Repo.preload(build, project: :account)
    project = build.project
    candidates = baseline_candidates(build, project)
    start_sha = build.merge_base_sha || build.git_commit_sha

    cond do
      candidates == [] ->
        nil

      candidate = build.merge_base_sha && Enum.find(candidates, &(&1.git_commit_sha == build.merge_base_sha)) ->
        candidate

      candidate = start_sha && nearest_in_history(project, build, start_sha, candidates) ->
        candidate

      true ->
        Enum.find(candidates, &(&1.git_branch == project.default_branch))
    end
  end

  defp nearest_in_history(project, build, sha, candidates) do
    with url when is_binary(url) <- build.git_remote_url_origin,
         repository_id when not is_nil(repository_id) <- GitHistory.existing_repository_id(project.account_id, url),
         shas = candidates |> Enum.map(& &1.git_commit_sha) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
         {nearest_sha, _distance} <- GitHistory.nearest_ancestor(repository_id, sha, shas) do
      Enum.find(candidates, &(&1.git_commit_sha == nearest_sha))
    else
      _ -> nil
    end
  end

  # Newest first, so the first match of each rule is the latest build.
  defp baseline_candidates(build, project) do
    Repo.all(
      from(b in Build,
        where:
          b.project_id == ^project.id and b.set_name == ^build.set_name and b.id != ^build.id and
            b.state == "processed" and b.inserted_at <= ^build.inserted_at and
            (b.git_branch == ^project.default_branch or not is_nil(b.approved_at)),
        order_by: [desc: b.inserted_at, desc: b.id],
        limit: @baseline_candidates_limit
      )
    )
  end

  # Commits

  # Worst first: a commit's status is its worst set's.
  @verdict_order ~w(processing failed rejected needs_review approved passed baseline)

  def get_commit(project, sha) do
    case Repo.one(from(c in Commit, where: c.project_id == ^project.id and c.git_commit_sha == ^sha)) do
      %Commit{runs_count: count} = commit when count > 0 ->
        {:ok, Repo.preload(commit, approved_by_account: :user, rejected_by_account: :user)}

      _ ->
        {:error, :not_found}
    end
  end

  @doc "A commit's builds, newest first: every set, shard and rerun uploaded for it."
  def commit_builds(project, sha) do
    Repo.preload(commit_builds_without_reviewers(project, sha), approved_by_account: :user, rejected_by_account: :user)
  end

  # What refreshing a commit reads: the reviews' account ids, not the reviewers'
  # users, which the processor role that runs the comparison can't read.
  defp commit_builds_without_reviewers(project, sha) do
    Repo.all(
      from(b in Build,
        where: b.project_id == ^project.id and b.git_commit_sha == ^sha,
        order_by: [desc: b.inserted_at, desc: b.id],
        preload: [:baseline_build]
      )
    )
  end

  @doc """
  A commit's images, pooled over its processed builds the way coverage pools
  a commit's runs: within each set, an image is the latest build's that
  rendered it, so shards complete each other and a rerun replaces an earlier
  run. An image no build rendered is removed if a build found it missing, or
  else skipped: a shard that doesn't render an image reports it missing, and
  every build of a commit renders the same code, so one rendering outweighs
  it. Each image carries its `set_name`.
  """
  def commit_images(project, sha) do
    project |> commit_builds(sha) |> Enum.reverse() |> pooled_images()
  end

  # `builds` oldest first, so a later build's image replaces an earlier one's.
  defp pooled_images(builds) do
    builds = Enum.filter(builds, &(&1.state == "processed"))
    ids = Enum.map(builds, & &1.id)
    images_by_build = Enum.group_by(Repo.all(from(i in Image, where: i.build_id in ^ids)), & &1.build_id)

    builds
    |> Enum.group_by(& &1.set_name)
    |> Enum.flat_map(fn {set_name, set_builds} ->
      # The latest image per name and kind; a rendering beats a removal, which beats a skip.
      by_kind =
        for build <- set_builds, image <- Map.get(images_by_build, build.id, []), reduce: %{} do
          acc -> Map.put(acc, {pooled_kind(image), image.name}, image)
        end

      by_kind
      |> Enum.group_by(fn {{_kind, name}, _image} -> name end, fn {{kind, _name}, image} -> {kind, image} end)
      |> Enum.map(fn {_name, kinds} -> kinds |> Enum.min_by(&elem(&1, 0)) |> elem(1) end)
      |> Enum.map(&%{&1 | set_name: set_name})
    end)
    |> Enum.sort_by(&{&1.set_name, Map.get(@status_order, &1.status, 6), &1.name})
  end

  defp pooled_kind(%Image{status: "removed"}), do: 1
  defp pooled_kind(%Image{status: "skipped"}), do: 2
  defp pooled_kind(%Image{}), do: 0

  @doc """
  Approves the changes of every build of the commit that has some, as
  `approve_build/2` does for one, and returns the republished commit.
  """
  def approve_commit(project, sha, reviewer), do: review_commit(project, sha, reviewer, &approve_build/2)

  @doc "Rejects the changes of every build of the commit that has some."
  def reject_commit(project, sha, reviewer), do: review_commit(project, sha, reviewer, &reject_build/2)

  defp review_commit(project, sha, reviewer, review) do
    case project |> commit_builds(sha) |> Enum.filter(&reviewable?(&1, project)) do
      [] ->
        {:error, :not_reviewable}

      builds ->
        Enum.each(builds, &({:ok, _} = review.(&1, reviewer)))
        get_commit(project, sha)
    end
  end

  @doc """
  The commit's CI signalled that every job reported, the signal that also
  completes its coverage (`tuist coverage complete`). It may arrive before
  any build of the commit, and is kept until one does.
  """
  def signal_complete(project, sha) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(
      %Commit{project_id: project.id, git_commit_sha: sha, completed_at: now, inserted_at: now, updated_at: now},
      on_conflict: from(c in Commit, update: [set: [completed_at: fragment("COALESCE(?, ?)", c.completed_at, ^now)]]),
      conflict_target: [:project_id, :git_commit_sha]
    )

    refresh_commit(project, sha)
  end

  @doc """
  Republishes the commit's row from its builds. Called whenever one of them
  changes, under a lock per commit, so the last write reads every change.
  """
  def refresh_commit(_project, sha) when sha in [nil, ""], do: nil

  def refresh_commit(project, sha) do
    {:ok, commit} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["snapshot_commit:#{project.id}:#{sha}"])
        builds = project |> commit_builds_without_reviewers(sha) |> Enum.reverse()
        attrs = commit_attrs(project, builds, pooled_images(builds))
        now = DateTime.truncate(DateTime.utc_now(), :second)

        Repo.insert!(
          struct(
            Commit,
            Map.merge(attrs, %{project_id: project.id, git_commit_sha: sha, inserted_at: now, updated_at: now})
          ),
          on_conflict: {:replace, Map.keys(attrs) ++ [:updated_at]},
          conflict_target: [:project_id, :git_commit_sha],
          returning: true
        )
      end)

    commit
  end

  defp commit_attrs(project, builds, images) do
    images_by_set = Enum.group_by(images, & &1.set_name)
    builds_by_id = Map.new(builds, &{&1.id, &1})
    newest_first = Enum.reverse(builds)

    status =
      builds
      |> Enum.group_by(& &1.set_name)
      |> Enum.map(fn {set_name, set_builds} ->
        set_status(project, set_builds, Map.get(images_by_set, set_name, []), builds_by_id)
      end)
      |> Enum.min_by(&Enum.find_index(@verdict_order, fn verdict -> verdict == &1 end), fn -> "processing" end)

    counts = Enum.frequencies_by(images, & &1.status)
    baseline = Enum.find_value(newest_first, &(&1.state == "processed" && &1.baseline_build))

    Map.merge(
      %{
        git_branch: Enum.find_value(newest_first, & &1.git_branch),
        pull_request_number: Enum.find_value(newest_first, & &1.pull_request_number),
        pull_request_title: Enum.find_value(newest_first, & &1.pull_request_title),
        status: status,
        unchanged_count: Map.get(counts, "unchanged", 0),
        changed_count: Map.get(counts, "changed", 0),
        added_count: Map.get(counts, "added", 0),
        removed_count: Map.get(counts, "removed", 0),
        renamed_count: Map.get(counts, "renamed", 0),
        skipped_count: Map.get(counts, "skipped", 0),
        runs_count: length(builds),
        set_names: builds |> Enum.map(& &1.set_name) |> Enum.uniq() |> Enum.sort(),
        baseline_commit_sha: baseline && baseline.git_commit_sha,
        baseline_git_branch: baseline && baseline.git_branch,
        last_uploaded_at: Enum.find_value(newest_first, & &1.inserted_at)
      },
      commit_review(status, builds)
    )
  end

  # A set's verdict over its builds: its latest build decides whether it is
  # still processing, its pooled images whether anything changed, and the
  # reviews of the builds those changes come from whether they were approved.
  defp set_status(project, set_builds, images, builds_by_id) do
    latest = List.last(set_builds)
    changes = Enum.filter(images, &(&1.status in ["changed", "removed"]))

    cond do
      latest.state in ["uploading", "processing"] ->
        "processing"

      not Enum.any?(set_builds, &(&1.state == "processed")) ->
        "failed"

      default_branch?(latest, project) ->
        "baseline"

      changes == [] ->
        "passed"

      true ->
        reviewed = changes |> Enum.map(& &1.build_id) |> Enum.uniq() |> Enum.map(&Map.fetch!(builds_by_id, &1))

        cond do
          Enum.any?(reviewed, & &1.rejected_at) -> "rejected"
          Enum.all?(reviewed, & &1.approved_at) -> "approved"
          true -> "needs_review"
        end
    end
  end

  @review_fields [
    :approved_at,
    :approved_by_account_id,
    :approved_by_github_handle,
    :rejected_at,
    :rejected_by_account_id,
    :rejected_by_github_handle
  ]

  # The review the commit's status comes from: the latest rejection of a
  # rejected commit, or the latest approval of an approved one.
  defp commit_review(status, builds) when status in ["approved", "rejected"] do
    at = if status == "approved", do: :approved_at, else: :rejected_at
    reviewed = builds |> Enum.filter(&Map.get(&1, at)) |> Enum.max_by(&Map.get(&1, at), DateTime)
    Map.new(@review_fields, &{&1, Map.get(reviewed, &1)})
  end

  defp commit_review(_status, _builds), do: Map.new(@review_fields, &{&1, nil})

  # Library

  @doc """
  Where the project's current baselines come from: for each set, the latest
  default-branch commit that processed it. A list of
  `%{set_name, git_commit_sha, uploaded_at}`, by set name.
  """
  def library_sources(project) do
    Repo.all(library_sources_query(project))
  end

  @doc """
  A page of the project's current baselines: each set's images at its
  `library_sources/1` commit, pooled over that commit's shards and reruns as
  `commit_images/2` pools them, without the removed ones. Ordered by group
  and name. Options: `:set_name`, `:group` (exact), `:search` (a substring
  of the name, display name, group or a `key=value` tag, case-insensitive),
  `:page` and
  `:page_size` (48). Returns `%{images: [...], total_count: n}`, where each
  image is a map with the `Image` fields the library shows and its
  `set_name`.
  """
  def list_library_images(project, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 48)
    query = library_images_query(project, opts)

    images =
      Repo.all(
        from(i in query,
          order_by: [
            asc: fragment("coalesce(?, '')", i.group),
            asc: coalesce(i.display_name, i.name),
            asc: i.name,
            asc: i.set_name
          ],
          limit: ^page_size,
          offset: ^((page - 1) * page_size)
        )
      )

    %{images: images, total_count: Repo.aggregate(query, :count)}
  end

  @doc "The groups of the library's images, sorted, each with how many images it holds."
  def library_groups(project) do
    Repo.all(
      from(i in library_images_query(project, []),
        where: not is_nil(i.group),
        group_by: i.group,
        order_by: i.group,
        select: %{group: i.group, count: count()}
      )
    )
  end

  @doc "How many images `list_library_images/2` holds with the same filters."
  def count_library_images(project, opts \\ []), do: Repo.aggregate(library_images_query(project, opts), :count)

  defp library_sources_query(project) do
    from(b in Build,
      where:
        b.project_id == ^project.id and b.state == "processed" and b.git_branch == ^project.default_branch and
          not is_nil(b.git_commit_sha),
      distinct: b.set_name,
      order_by: [asc: b.set_name, desc: b.inserted_at, desc: b.id],
      select: %{set_name: b.set_name, git_commit_sha: b.git_commit_sha, uploaded_at: b.inserted_at}
    )
  end

  # The same choice `pooled_images/1` makes, per set and name: a rendering
  # beats a removal, which beats a skip, and a later build beats an earlier one.
  defp library_images_query(project, opts) do
    pooled =
      from(i in Image,
        join: b in Build,
        on: b.id == i.build_id,
        join: s in subquery(library_sources_query(project)),
        on: s.set_name == b.set_name and s.git_commit_sha == b.git_commit_sha,
        where: b.project_id == ^project.id and b.state == "processed",
        distinct: [asc: b.set_name, asc: i.name],
        order_by: [
          asc: fragment("CASE ? WHEN 'removed' THEN 1 WHEN 'skipped' THEN 2 ELSE 0 END", i.status),
          desc: b.inserted_at,
          desc: b.id
        ],
        select: %{
          id: i.id,
          build_id: i.build_id,
          set_name: b.set_name,
          name: i.name,
          display_name: i.display_name,
          group: i.group,
          tags: i.tags,
          content_hash: i.content_hash,
          width: i.width,
          height: i.height,
          status: i.status
        }
      )

    from(i in subquery(pooled), where: i.status != "removed")
    |> where_library_set(Keyword.get(opts, :set_name))
    |> where_library_group(Keyword.get(opts, :group))
    |> where_library_search(Keyword.get(opts, :search))
  end

  defp where_library_set(query, nil), do: query
  defp where_library_set(query, set_name), do: where(query, [i], i.set_name == ^set_name)

  defp where_library_group(query, nil), do: query
  defp where_library_group(query, group), do: where(query, [i], i.group == ^group)

  defp where_library_search(query, search) when search in [nil, ""], do: query

  defp where_library_search(query, search) do
    pattern = "%#{search |> String.downcase() |> String.replace(~w(\\ % _), &"\\#{&1}")}%"

    where(
      query,
      [i],
      like(fragment("lower(?)", i.name), ^pattern) or like(fragment("lower(?)", i.display_name), ^pattern) or
        like(fragment("lower(?)", i.group), ^pattern) or
        fragment(
          "EXISTS (SELECT 1 FROM jsonb_each_text(?) AS t WHERE lower(t.key) LIKE ? OR lower(t.value) LIKE ? OR lower(t.key || '=' || t.value) LIKE ?)",
          i.tags,
          ^pattern,
          ^pattern,
          ^pattern
        )
    )
  end

  @doc """
  One image's history in a set on the default branch, newest first: the
  builds where the image first appeared, looked different from the version
  before, or was removed, each with its comparison against its baseline, as
  `%{image: image, build: build}`. Other branches' builds are proposals that
  may never land, so they aren't part of it.

  Returns a page of `:limit` (10) versions as `%{versions: [...], more?:
  boolean}`; `:before` takes the last version's build to read the page after it.
  """
  def image_history(project, set_name, name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    # A version is a default-branch build whose image differs from the
    # previous one's: compared by content rather than by the build's status,
    # since a build compared with an approved pull request reads as unchanged.
    renderings =
      from(i in Image,
        join: b in Build,
        on: b.id == i.build_id,
        where:
          b.project_id == ^project.id and b.set_name == ^set_name and b.state == "processed" and
            b.git_branch == ^project.default_branch and i.name == ^name and i.status != "skipped",
        windows: [history: [order_by: [asc: b.inserted_at, asc: b.id]]],
        select: %{
          image_id: i.id,
          build_id: b.id,
          inserted_at: b.inserted_at,
          content_hash: i.content_hash,
          previous_hash: over(lag(i.content_hash), :history)
        }
      )

    rows =
      from(r in subquery(renderings),
        join: i in Image,
        on: i.id == r.image_id,
        join: b in Build,
        on: b.id == r.build_id,
        where: fragment("? IS DISTINCT FROM ?", r.content_hash, r.previous_hash),
        order_by: [desc: r.inserted_at, desc: r.build_id],
        limit: ^(limit + 1),
        select: {i, b}
      )
      |> where_before(Keyword.get(opts, :before))
      |> Repo.all()

    %{
      versions:
        rows
        |> Enum.take(limit)
        |> Enum.map(fn {image, build} -> %{image: %{image | set_name: set_name}, build: build} end),
      more?: length(rows) > limit
    }
  end

  defp where_before(query, nil), do: query

  defp where_before(query, %Build{inserted_at: inserted_at, id: id}) do
    where(query, [r], r.inserted_at < ^inserted_at or (r.inserted_at == ^inserted_at and r.build_id < ^id))
  end

  @doc """
  Reads an image's bytes: `:head`, `:baseline`, `:diff` or `:thumbnail`,
  which falls back to `:head` for an image stored without one.
  """
  def image_binary(project, %Image{} = image, :head),
    do: read(project, image.content_hash && blob_key(project, image.content_hash))

  def image_binary(project, %Image{} = image, :baseline),
    do: read(project, image.baseline_content_hash && blob_key(project, image.baseline_content_hash))

  def image_binary(project, %Image{} = image, :diff), do: read(project, image.diff_key)

  def image_binary(project, %Image{} = image, :thumbnail) do
    with {:error, :not_found} <- read(project, image.content_hash && thumbnail_key(project, image.content_hash)) do
      image_binary(project, image, :head)
    end
  end

  defp read(_project, nil), do: {:error, :not_found}

  defp read(project, key) do
    case Storage.get_object_as_string(key, project.account) do
      nil -> {:error, :not_found}
      binary -> {:ok, binary}
    end
  end
end
