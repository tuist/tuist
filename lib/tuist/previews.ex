defmodule Tuist.Previews do
  @moduledoc """
  A module to deal with Tuist Previews.
  """
  import Ecto.Query

  alias Tuist.Previews.Preview
  alias Tuist.Projects.Project
  alias Tuist.Repo

  def create_preview(
        %{
          project: %Project{} = project,
          type: type,
          display_name: display_name,
          bundle_identifier: bundle_identifier,
          version: version,
          supported_platforms: supported_platforms,
          git_branch: git_branch,
          git_commit_sha: git_commit_sha,
          ran_by_account_id: ran_by_account_id
        },
        opts \\ []
      ) do
    %Preview{}
    |> Preview.create_changeset(%{
      project_id: project.id,
      type: type,
      display_name: display_name,
      bundle_identifier: bundle_identifier,
      version: version,
      supported_platforms: supported_platforms,
      inserted_at: Keyword.get(opts, :inserted_at),
      inserted_at_naive:
        opts
        |> Keyword.get(:inserted_at, DateTime.utc_now())
        |> DateTime.shift_zone!("Etc/UTC")
        |> DateTime.to_naive(),
      git_branch: git_branch,
      git_commit_sha: git_commit_sha,
      ran_by_account_id: ran_by_account_id
    })
    |> Repo.insert!()
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
    {previews, _meta} =
      list_previews(
        %{
          first: 20,
          filters: [
            %{field: :project_id, op: :==, value: project.id}
          ],
          order_by: [:inserted_at_naive],
          order_directions: [:desc]
        },
        distinct: [:bundle_identifier],
        preload: [:command_event, [project: :account]]
      )

    previews
  end

  defp query_with_distinct_bundle_identifier_when_needed(query, attrs, opts) do
    distinct_bundle_identifier =
      opts
      |> Keyword.get(:distinct, [])
      |> Enum.member?(:bundle_identifier)

    order_by =
      attrs |> Map.get(:order_by, [:inserted_at_naive]) |> hd()

    order_direction = attrs |> Map.get(:order_directions, [:desc]) |> hd()

    if distinct_bundle_identifier do
      preview_ids =
        from(p in Preview)
        |> Flop.query(%Flop{}, for: Preview)
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

  def get_latest_preview(%Project{} = project) do
    Preview
    # This is here for legacy reasons before preview had columns for git_branch and git_commit_sha.
    # We can remove this in the future once the majority of users are on a Tuist version 4.45.0 or later.
    |> join(:left, [p], e in assoc(p, :command_event), as: :command_event)
    |> preload(:command_event)
    |> where(
      [p, e],
      p.project_id == ^project.id and
        (p.git_branch == ^project.default_branch or e.git_branch == ^project.default_branch)
    )
    |> order_by(desc: :inserted_at_naive)
    |> limit(1)
    |> preload(:command_event)
    |> Repo.one()
  end

  def get_preview_by_id(id, opts \\ []) do
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

  def get_storage_key(%{account_handle: account_handle, project_handle: project_handle, preview_id: preview_id}) do
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/previews/#{preview_id}.zip"
  end

  def get_icon_storage_key(%{account_handle: account_handle, project_handle: project_handle, preview_id: preview_id}) do
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/previews/#{preview_id}/icon.png"
  end

  def get_supported_platforms_case_values(%Preview{supported_platforms: supported_platforms}) do
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
end
