defmodule Tuist.Previews do
  @moduledoc """
  A module to deal with Tuist Previews.
  """
  alias Tuist.Repo
  alias Tuist.Projects.Project
  alias Tuist.Previews.Preview

  def create_preview(
        %{
          project: %Project{} = project,
          type: type,
          display_name: display_name,
          bundle_identifier: bundle_identifier,
          version: version,
          supported_platforms: supported_platforms
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
      inserted_at: Keyword.get(opts, :inserted_at)
    })
    |> Repo.insert!()
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
