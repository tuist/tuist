defmodule Tuist.Artifacts do
  @moduledoc """
  Retains immutable artifact closures independently of their consumers.
  """
  import Ecto.Query, only: [from: 2]

  alias Tuist.Accounts.Account
  alias Tuist.Artifacts.Package
  alias Tuist.Artifacts.ProjectApplicationsWorker
  alias Tuist.Artifacts.Publication
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Storage.RetentionPolicy

  def destination(project), do: "project:#{project.id}"

  def get(project, key) do
    case Repo.get_by(Publication, project_id: project.id, key: key) do
      nil ->
        {:error, :not_found}

      publication ->
        if retained?(publication, project.account) do
          if publication.committed, do: {:ok, publication}, else: {:error, :not_found}
        else
          expire(publication)
          {:error, :expired}
        end
    end
  end

  def retained?(%Publication{expired: true}, _account), do: false

  def retained?(publication, _account) do
    days = if Environment.tuist_hosted?(), do: 30, else: Map.get(Environment.artifact_retention_days(), :app_previews)

    is_nil(days) or
      DateTime.compare(publication.inserted_at, RetentionPolicy.cutoff(:preview_app_build, :air, days)) != :lt
  end

  def expire(%Publication{expired: true} = publication), do: publication
  def expire(publication), do: publication |> Ecto.Changeset.change(expired: true) |> Repo.update!()

  def put_content(project, key, digest, path) do
    with true <- Package.valid_digest?(key) and Package.valid_digest?(digest),
         :ok <- writable(project, key),
         {:ok, upload_id} <- admit_upload(project.account_id),
         {:ok, _} <- Storage.upload_file(path, Package.storage_key(project, key, digest), project.account) do
      Repo.delete_all(from u in "artifact_uploads", where: u.id == ^upload_id)
      :ok
    else
      false -> {:error, :invalid_digest}
      {:error, reason} when reason in [:expired, :already_committed] -> {:error, reason}
      # An unconfirmed storage write may still complete. Keep its claim so
      # account erasure continues sweeping even if this request or replica dies.
      {:error, _} -> {:error, :storage_unavailable}
    end
  end

  defp admit_upload(account_id) do
    Repo.transaction(fn ->
      # Account deletion must either observe this durable claim or finish before
      # admission. Never hold the SQL lock during object storage I/O.
      if !Repo.one(from a in Account, where: a.id == ^account_id, select: a.id, lock: "FOR KEY SHARE") do
        Repo.rollback(:expired)
      end

      {1, [%{id: id}]} =
        Repo.insert_all("artifact_uploads", [%{account_id: account_id, inserted_at: DateTime.utc_now()}],
          returning: [:id]
        )

      id
    end)
  end

  def uploads_pending?(account_id), do: Repo.exists?(from u in "artifact_uploads", where: u.account_id == ^account_id)

  defp writable(project, key) do
    case get(project, key) do
      {:error, :not_found} -> :ok
      {:ok, _} -> {:error, :already_committed}
      error -> error
    end
  end

  def commit(project, key, intent, creator_id) do
    with :ok <- Package.validate_intent(intent),
         true <- key == Package.key(intent),
         {:ok, publication} <- stage(project, key, intent, creator_id) do
      if publication.committed do
        {:ok, publication}
      else
        # The durable staging row pins the closure against retention. Storage I/O
        # must not hold a SQL connection or an advisory lock.
        with {:ok, contents} <- Package.closure(project, key, intent["root"]) do
          finalize(project, publication, contents)
        end
      end
    else
      false -> {:error, :intent_key_mismatch}
      error -> error
    end
  end

  defp stage(project, key, intent, creator_id) do
    fn ->
      lock(project.id, key)

      publication = Repo.get_by(Publication, project_id: project.id, key: key)

      if publication do
        publication
      else
        Repo.insert!(%Publication{
          project_id: project.id,
          created_by_account_id: creator_id,
          key: key,
          intent: intent,
          contents: %{}
        })
      end
    end
    |> Repo.transaction()
    |> retained_result(project)
  end

  defp finalize(project, publication, contents) do
    fn ->
      lock(project.id, publication.key)
      current = Repo.get!(Publication, publication.id)

      cond do
        not retained?(current, project.account) ->
          expire(current)

        current.committed ->
          current

        true ->
          current = current |> Ecto.Changeset.change(contents: contents, committed: true) |> Repo.update!()

          %{publication_id: current.id}
          |> ProjectApplicationsWorker.new()
          |> Oban.insert!()

          current
      end
    end
    |> Repo.transaction()
    |> retained_result(project)
  end

  defp retained_result({:ok, publication}, project) do
    if retained?(publication, project.account) do
      {:ok, publication}
    else
      expire(publication)
      {:error, :expired}
    end
  end

  defp retained_result(error, _project), do: error

  # Commit and retention must agree before either acknowledges or removes a closure.
  def lock(project_id, key) do
    Repo.query!("SET LOCAL lock_timeout = '5s'")
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["artifact:#{project_id}:#{key}"])
  end

  def receipt(project, publication, url) do
    %{
      schema: "once.publication_receipt.v1",
      key: publication.key,
      root: publication.intent["root"],
      destination: destination(project),
      url: url
    }
  end

  def content_url(project, publication, digest) do
    with true <- Map.has_key?(publication.contents, digest),
         true <- retained?(publication, project.account) do
      {:ok, Storage.generate_download_url(Package.storage_key(project, publication.key, digest), project.account)}
    else
      _ -> {:error, :not_found}
    end
  end
end
