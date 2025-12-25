defmodule Tuist.AppBuilds do
  @moduledoc """
  A module to deal with Tuist app builds and associated previews.
  """
  import Ecto.Query

  alias Tuist.AppBuilds.AppBuild
  alias Tuist.AppBuilds.Preview
  alias Tuist.Projects.Project
  alias Tuist.Repo

  def create_preview(attrs) do
    %Preview{}
    |> Preview.create_changeset(attrs)
    |> Repo.insert()
  end

  def find_or_create_preview(
        %{
          project_id: project_id,
          bundle_identifier: bundle_identifier,
          version: version,
          git_commit_sha: git_commit_sha,
          created_by_account_id: created_by_account_id,
          display_name: display_name
        } = attrs
      ) do
    track = Map.get(attrs, :track) || ""

    preview =
      from(p in Preview)
      |> where([p], p.project_id == ^project_id)
      |> then(&if(is_nil(display_name), do: &1, else: where(&1, [p], p.display_name == ^display_name)))
      |> then(
        &if(is_nil(bundle_identifier),
          do: &1,
          else: where(&1, [p], p.bundle_identifier == ^bundle_identifier)
        )
      )
      |> then(
        &if(is_nil(created_by_account_id),
          do: &1,
          else: where(&1, [p], p.created_by_account_id == ^created_by_account_id)
        )
      )
      |> then(
        &if(is_nil(git_commit_sha),
          do: &1,
          else: where(&1, [p], p.git_commit_sha == ^git_commit_sha)
        )
      )
      |> then(&if(is_nil(version), do: &1, else: where(&1, [p], p.version == ^version)))
      |> where([p], p.track == ^track)
      |> limit(1)
      |> Repo.one()

    if is_nil(preview) do
      create_preview(Map.put(attrs, :track, track))
    else
      {:ok, preview}
    end
  end

  def app_build_by_id(id, opts \\ []) do
    if Tuist.UUIDv7.valid?(id) do
      preload = Keyword.get(opts, :preload, [])
      app_build = Repo.get(AppBuild, id)

      case app_build do
        nil -> {:error, :not_found}
        %AppBuild{} = app_build -> {:ok, Repo.preload(app_build, preload)}
      end
    else
      {:error, "The provided app build identifier #{id} doesn't have a valid format."}
    end
  end

  @doc """
  Finds the latest preview on the same track (bundle identifier, git branch, and track) as the app build
  identified by the given binary ID and build version.

  Only previews that have at least one app build with a matching supported platform are considered.

  Returns `{:ok, preview}` if found, `{:error, :not_found}` otherwise.
  """
  def latest_preview_for_binary_id_and_build_version(binary_id, build_version, %Project{} = project, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    with {:ok, app_build} <-
           app_build_by_binary_id_and_build_version(binary_id, build_version, preload: [:preview]),
         %Preview{bundle_identifier: bundle_identifier, git_branch: git_branch, track: track}
         when not is_nil(bundle_identifier) <- app_build.preview do
      normalized_track = track || ""

      supported_platforms_as_integers =
        Enum.map(
          app_build.supported_platforms,
          &Ecto.Enum.mappings(AppBuild, :supported_platforms)[&1]
        )

      preview =
        Repo.one(
          from(p in Preview,
            join: ab in AppBuild,
            on: ab.preview_id == p.id,
            where: p.project_id == ^project.id,
            where: p.bundle_identifier == ^bundle_identifier,
            where: p.git_branch == ^git_branch,
            where: p.track == ^normalized_track,
            where: fragment("? && ?", ab.supported_platforms, ^supported_platforms_as_integers),
            order_by: [desc: p.inserted_at],
            limit: 1,
            preload: ^preload
          )
        )

      case preview do
        nil -> {:error, :not_found}
        %Preview{} -> {:ok, preview}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  defp app_build_by_binary_id_and_build_version(binary_id, build_version, _opts)
       when is_nil(binary_id) or is_nil(build_version) do
    {:error, :not_found}
  end

  defp app_build_by_binary_id_and_build_version(binary_id, build_version, opts) do
    preload = Keyword.get(opts, :preload, [])

    case Repo.get_by(AppBuild, binary_id: binary_id, build_version: build_version) do
      nil -> {:error, :not_found}
      %AppBuild{} = app_build -> {:ok, Repo.preload(app_build, preload)}
    end
  end

  def create_app_build(attrs) do
    %AppBuild{}
    |> AppBuild.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_preview_with_app_build(preview_id, app_build) do
    preview = Repo.get!(Preview, preview_id)

    preview
    |> Preview.create_changeset(%{
      supported_platforms: Enum.uniq(preview.supported_platforms ++ app_build.supported_platforms)
    })
    |> Repo.update!()
  end

  def list_previews(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    Preview
    |> preload(^preload)
    |> query_with_supported_platforms_when_needed(opts)
    |> query_with_distinct_bundle_identifier_when_needed(attrs, opts)
    |> Flop.validate_and_run!(attrs, for: Preview)
  end

  @doc """
  Gets the latest previews with distinct bundle identifiers for a given project.
  """
  def latest_previews_with_distinct_bundle_ids(%Project{} = project) do
    filters = [
      %{field: :project_id, op: :==, value: project.id}
    ]

    filters =
      if is_nil(latest_preview(project, git_branch: project.default_branch)) do
        filters
      else
        filters ++ [%{field: :git_branch, op: :==, value: project.default_branch}]
      end

    {previews, _meta} =
      list_previews(
        %{
          first: 20,
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc]
        },
        distinct: [:bundle_identifier],
        preload: [:app_builds, project: :account]
      )

    previews
  end

  defp query_with_distinct_bundle_identifier_when_needed(query, attrs, opts) do
    distinct_bundle_identifier =
      opts
      |> Keyword.get(:distinct, [])
      |> Enum.member?(:bundle_identifier)

    order_by =
      attrs |> Map.get(:order_by, [:inserted_at]) |> hd()

    order_direction = attrs |> Map.get(:order_directions, [:desc]) |> hd()

    filters =
      attrs
      |> Map.get(:filters, [])
      |> Enum.map(&%Flop.Filter{field: &1.field, op: &1.op, value: &1.value})

    if distinct_bundle_identifier do
      preview_ids =
        from(p in Preview)
        |> Flop.query(%Flop{filters: filters}, for: Preview)
        |> order_by({^order_direction, ^order_by})
        |> distinct([p], p.bundle_identifier)
        |> select([p], p.id)

      where(query, [p], p.id in subquery(preview_ids))
    else
      query
    end
  end

  defp query_with_supported_platforms_when_needed(query, opts) do
    supported_platforms = Keyword.get(opts, :supported_platforms, nil)

    if is_nil(supported_platforms) do
      query
    else
      where(
        query,
        [p],
        fragment(
          "? && ?",
          p.supported_platforms,
          ^Enum.map(supported_platforms, &Ecto.Enum.mappings(Preview, :supported_platforms)[&1])
        )
      )

      # We're using a fragment here as Ecto doesn't have first-party support for the && operator.
      # && operator finds rows where arrays have any elements in common.
      # You can find the docs for the && operator here: https://www.postgresql.org/docs/current/functions-array.html
      # Because the arrays are enums and we're using a fragment, we also need to map the preview_supported_platforms to raw integer values.
    end
  end

  def latest_preview(%Project{} = project, opts \\ []) do
    git_branch = Keyword.get(opts, :git_branch, project.default_branch)

    Preview
    |> where([p], p.project_id == ^project.id)
    |> then(&if(is_nil(git_branch), do: &1, else: where(&1, [p], p.git_branch == ^git_branch)))
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def preview_by_id(id, opts \\ []) do
    if Tuist.UUIDv7.valid?(id) do
      preload = Keyword.get(opts, :preload, [])
      preview = Preview |> Repo.get_by(id: id) |> Repo.preload(preload)

      case preview do
        nil -> {:error, :not_found}
        %Preview{} = preview -> {:ok, preview}
      end
    else
      {:error, "The provided preview ID #{id} doesn't have a valid format."}
    end
  end

  def storage_key(%{account_handle: account_handle, project_handle: project_handle, app_build_id: app_build_id}) do
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/previews/#{app_build_id}.zip"
  end

  def icon_storage_key(%{account_handle: account_handle, project_handle: project_handle, preview_id: preview_id}) do
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/previews/#{preview_id}/icon.png"
  end

  def supported_platforms_case_values(%Preview{supported_platforms: supported_platforms}) do
    if is_nil(supported_platforms) do
      []
    else
      Enum.map(supported_platforms, &platform_string/1)
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def platform_string(supported_platform) do
    case supported_platform do
      :ios -> "iOS"
      :ios_simulator -> "iOS Simulator"
      :tvos -> "tvOS"
      :tvos_simulator -> "tvOS Simulator"
      :watchos -> "watchOS"
      :watchos_simulator -> "watchOS Simulator"
      :visionos -> "visionOS"
      :visionos_simulator -> "visionOS Simulator"
      :macos -> "macOS"
    end
  end

  def latest_ipa_app_build_for_preview(%Preview{} = preview) do
    preview.app_builds
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find(&(&1.type == :ipa))
  end

  def latest_app_build(git_ref, %Project{} = project, opts \\ []) do
    supported_platform = Keyword.get(opts, :supported_platform)

    enum_el_type =
      case AppBuild.__schema__(:type, :supported_platforms) do
        {:array, el_type} -> el_type
        other -> raise "Unexpected type for supported_platforms: #{inspect(other)}"
      end

    latest_preview =
      from p in Preview,
        where: p.project_id == ^project.id and p.git_ref == ^git_ref,
        distinct: p.display_name,
        order_by: [asc: p.display_name, desc: p.inserted_at]

    app_build_query =
      from ab in AppBuild,
        where:
          ab.preview_id == parent_as(:p).id and
            (is_nil(type(^supported_platform, ^enum_el_type)) or
               fragment(
                 "? = ANY(?)",
                 type(^supported_platform, ^enum_el_type),
                 ab.supported_platforms
               )),
        order_by: [desc: ab.inserted_at],
        limit: 1

    query =
      from p in subquery(latest_preview),
        as: :p,
        inner_lateral_join: ab in subquery(app_build_query),
        on: true,
        order_by: [desc: p.inserted_at],
        limit: 1,
        select: ab

    Repo.one(query)
  end

  def delete_preview!(%Preview{} = preview) do
    Repo.delete!(preview)
  end
end
