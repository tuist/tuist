defmodule Tuist.Artifacts.PreviewIconWorker do
  @moduledoc false
  # Copies a publication's icon payload to the icon object of the preview projected
  # from it. It runs after the preview commits, so an icon that cannot be copied
  # never blocks the preview, and it writes nothing once the preview is gone.
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias Tuist.Artifacts
  alias Tuist.Artifacts.Package
  alias Tuist.Artifacts.Publication
  alias Tuist.Repo
  alias Tuist.Storage

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"publication_id" => publication_id, "preview_id" => preview_id, "icon" => icon}}) do
    with %Publication{} = publication <- Repo.get(Publication, publication_id),
         %{project: project} = publication <- Repo.preload(publication, project: :account),
         true <- Artifacts.retained?(publication, project.account),
         %Preview{} <- Repo.get(Preview, preview_id),
         {:ok, @png_signature <> _ = bytes} <- Package.read(project, publication.key, icon) do
      key =
        AppBuilds.icon_storage_key(%{
          account_handle: project.account.name,
          project_handle: project.name,
          preview_id: preview_id
        })

      Storage.put_object(key, bytes, project.account)
    else
      {:error, :storage_unavailable} = error -> error
      _ -> :ok
    end
  end
end
