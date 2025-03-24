defmodule Tuist.Previews do
  @moduledoc """
  A module to deal with Tuist Previews.
  """
  alias Tuist.Repo
  alias Tuist.Projects.Project
  alias Tuist.Previews.Preview
  import Ecto.Query

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
      git_branch: git_branch,
      git_commit_sha: git_commit_sha,
      ran_by_account_id: ran_by_account_id
    })
    |> Repo.insert!()
  end

  def list_previews(attrs, opts \\ []) do
    Preview
    |> preload(^Keyword.get(opts, :preload, []))
    |> query_with_supported_platforms_when_needed(opts)
    |> query_with_distinct_bundle_identifier_when_needed(opts)
    |> Flop.validate_and_run!(attrs, for: Preview)
  end

  defp query_with_distinct_bundle_identifier_when_needed(query, opts) do
    distinct_bundle_identifier =
      Keyword.get(opts, :distinct, [])
      |> Enum.member?(:bundle_identifier)

    if distinct_bundle_identifier do
      preview_ids =
        from(p in Preview)
        |> Flop.query(%Flop{}, for: Preview)
        |> distinct([p], p.bundle_identifier)
        |> select([p], p.id)

      query
      |> where([p], p.id in subquery(preview_ids))
    else
      query
    end
  end

  defp query_with_supported_platforms_when_needed(query, opts) do
    supported_platforms = opts |> Keyword.get(:supported_platforms, nil)

    if is_nil(supported_platforms) do
      query
    else
      query
      # We're using a fragment here as Ecto doesn't have first-party support for the && operator.
      # && operator finds rows where arrays have any elements in common.
      # You can find the docs for the && operator here: https://www.postgresql.org/docs/current/functions-array.html
      # Because the arrays are enums and we're using a fragment, we also need to map the preview_supported_platforms to raw integer values.
      |> where(
        [p],
        fragment(
          "? && ?",
          p.supported_platforms,
          ^(supported_platforms
            |> Enum.map(&Ecto.Enum.mappings(Preview, :supported_platforms)[&1]))
        )
      )
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
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> preload(:command_event)
    |> Repo.one()
  end

  def get_preview_by_id(id, opts \\ []) do
    if Tuist.UUIDv7.valid?(id) do
      preload = Keyword.get(opts, :preload, [])
      preview = Repo.get_by(Preview, id: id) |> Repo.preload(preload)

      case preview do
        nil -> {:error, :not_found}
        %Preview{} = preview -> {:ok, preview}
      end
    else
      {:error, "The provided preview ID #{id} doesn't have a valid format."}
    end
  end

  def get_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        preview_id: preview_id
      }) do
    "#{account_handle |> String.downcase()}/#{project_handle |> String.downcase()}/previews/#{preview_id}.zip"
  end

  def get_icon_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        preview_id: preview_id
      }) do
    "#{account_handle |> String.downcase()}/#{project_handle |> String.downcase()}/previews/#{preview_id}/icon.png"
  end

  def get_supported_platforms_case_values(%Preview{supported_platforms: supported_platforms}) do
    if is_nil(supported_platforms) do
      []
    else
      supported_platforms |> Enum.map(&supported_platform_strings/1)
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp supported_platform_strings(supported_platform) do
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
