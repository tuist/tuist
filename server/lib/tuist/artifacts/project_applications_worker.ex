defmodule Tuist.Artifacts.ProjectApplicationsWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 5

  import Ecto.Query

  alias Tuist.AppBuilds.AppBuild
  alias Tuist.AppBuilds.Preview
  alias Tuist.Artifacts
  alias Tuist.Artifacts.Package
  alias Tuist.Artifacts.Publication
  alias Tuist.Repo
  alias Uniq.UUID

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"publication_id" => id}}) do
    case Repo.get(Publication, id) do
      nil -> :ok
      %{committed: false} -> :ok
      %{projected: true} -> :ok
      publication -> project(Repo.preload(publication, project: :account))
    end
  end

  defp project(publication) do
    project = publication.project
    Tuist.Observability.set_selection(%{selected_project: project})

    if Artifacts.retained?(publication, project.account) do
      with {:ok, root} <- Package.read_json(project, publication.key, publication.intent["root"]),
           {:ok, applications} <- applications(project, publication, root["members"]),
           {:ok, _} <- persist(publication, applications) do
        :ok
      end
    else
      :ok
    end
  end

  defp applications(project, publication, members) do
    Enum.reduce_while(members, {:ok, []}, fn {name, member}, {:ok, apps} ->
      with {:ok, manifest} <- Package.read_json(project, publication.key, member["artifact"]),
           {:ok, app} <- application(project, publication, name, manifest) do
        {:cont, {:ok, if(is_nil(app), do: apps, else: [app | apps])}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp application(project, publication, name, manifest) do
    interfaces = manifest["interfaces"]
    interface = interfaces["dev.once.apple-install.v2"] || interfaces["dev.once.android-install.v1"]

    if interface do
      with %{"spec" => %{"metadata_payload" => payload}} when is_binary(payload) <- interface,
           %{} = descriptor <- manifest["payloads"][payload],
           {:ok, metadata} <- Package.read_json(project, publication.key, descriptor) do
        attributes = app_attributes(metadata)

        if attributes && valid_attributes?(attributes) do
          id = UUID.uuid5(:oid, "artifact:#{publication.id}:#{name}")
          {:ok, Map.merge(attributes, %{id: id, payload: manifest["payloads"][interface["payload"]]})}
        else
          {:ok, nil}
        end
      else
        {:error, reason} when reason in [:invalid_descriptor, :invalid_content] -> {:ok, nil}
        {:error, _} = error -> error
        _ -> {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  defp app_attributes(
         %{"schema" => "once.android_application.v1", "signature_verified" => true, "application_id" => identifier} =
           metadata
       ) do
    %{
      type: :apk,
      platforms: [:android],
      identifier: identifier,
      name: identifier,
      version: metadata["version_name"],
      build_version: metadata["version_code"]
    }
  end

  defp app_attributes(
         %{"schema" => "once.apple_application.v1", "signature_verified" => true, "signing" => "ad_hoc"} = metadata
       ) do
    platform =
      case {metadata["platform"], metadata["sdk_variant"]} do
        {"macos", "device"} -> :macos
        {"ios", "simulator"} -> :ios_simulator
        {"tvos", "simulator"} -> :tvos_simulator
        {"watchos", "simulator"} -> :watchos_simulator
        {"visionos", "simulator"} -> :visionos_simulator
        _ -> nil
      end

    if platform do
      %{
        type: :app_bundle,
        platforms: [platform],
        identifier: metadata["bundle_identifier"],
        name: metadata["display_name"],
        version: metadata["version"],
        build_version: metadata["build_version"]
      }
    end
  end

  defp app_attributes(_), do: nil

  defp valid_attributes?(attributes) do
    is_binary(attributes.identifier) and byte_size(attributes.identifier) in 1..255 and
      Enum.all?([attributes.identifier, attributes.name, attributes.version, attributes.build_version], fn value ->
        is_nil(value) or (is_binary(value) and byte_size(value) <= 255 and not String.contains?(value, "\0"))
      end)
  end

  defp persist(publication, applications) do
    Repo.transaction(fn ->
      current = Repo.one!(from p in Publication, where: p.id == ^publication.id, lock: "FOR UPDATE")

      cond do
        not Artifacts.retained?(current, publication.project.account) ->
          :expired

        current.projected ->
          :already_projected

        true ->
          Enum.each(applications, fn app ->
            %Preview{id: app.id}
            |> Preview.create_changeset(%{
              project_id: publication.project_id,
              created_by_account_id: publication.created_by_account_id,
              bundle_identifier: app.identifier,
              display_name: app.name,
              version: app.version,
              supported_platforms: app.platforms,
              git_commit_sha: publication.intent["revision"],
              track: publication.intent["track"] || "",
              visibility: publication.project.default_previews_visibility,
              inserted_at: publication.inserted_at
            })
            |> Repo.insert!()

            %AppBuild{
              id: app.id,
              artifact_storage_key: Package.storage_key(publication.project, publication.key, app.payload["digest"])
            }
            |> AppBuild.create_changeset(%{
              preview_id: app.id,
              type: app.type,
              supported_platforms: app.platforms,
              build_version: app.build_version,
              inserted_at: publication.inserted_at
            })
            |> Repo.insert!()
          end)

          current |> Ecto.Changeset.change(projected: true) |> Repo.update!()
      end
    end)
  end
end
