defmodule Tuist.Artifacts.RetentionWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :storage_retention,
    max_attempts: 3,
    unique: [keys: [:account_id], period: :infinity, states: :incomplete]

  import Ecto.Query, only: [from: 2]
  import Tuist.Storage.Workers.ArtifactRetentionWorker

  alias Tuist.Accounts.Account
  alias Tuist.Artifacts
  alias Tuist.Artifacts.Package
  alias Tuist.Artifacts.Publication
  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.Storage.RetentionPolicy

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args} = job) do
    with {:enabled, days} <- effective_retention_days(args, :app_previews),
         %Account{} = account <- Repo.get(Account, account_id),
         {:ok, %{body: body}} <-
           Storage.list_objects("#{account.id}/", account, max_keys: 500, continuation_token: args["continuation_token"]),
         :ok <- sweep(account, Map.get(body, :contents, []), days) do
      if Map.get(body, :is_truncated) in [true, "true"] do
        reschedule_with_args(job, Map.put(args, "continuation_token", body.next_continuation_token))
      else
        :ok
      end
    else
      :disabled -> :ok
      nil -> :ok
      error -> error
    end
  end

  defp sweep(account, objects, days) do
    objects
    |> Enum.group_by(&publication_key(&1.key))
    |> Enum.reduce_while(:ok, fn
      {nil, _}, :ok ->
        {:cont, :ok}

      {{project_id, key}, objects}, :ok ->
        with {:ok, keys} <- mark_expired(account, project_id, key, objects, days),
             :ok <- Storage.delete_objects(keys, account) do
          {:cont, :ok}
        else
          error -> {:halt, error}
        end
    end)
  end

  defp mark_expired(account, project_id, key, objects, days) do
    Repo.transaction(fn ->
      Artifacts.lock(project_id, key)
      publication = Repo.get_by(Publication, project_id: project_id, key: key)
      cutoff = RetentionPolicy.cutoff(:preview_app_build, :air, days)

      publication =
        if publication && (publication.expired || DateTime.before?(publication.inserted_at, cutoff)),
          do: Artifacts.expire(publication),
          else: publication

      keys = objects |> Enum.filter(&expired?(&1, publication, cutoff)) |> Enum.map(& &1.key)

      if is_nil(publication) and keys != [] and
           Repo.one(
             from p in Project,
               where: p.id == ^project_id and p.account_id == ^account.id,
               select: p.id,
               lock: "FOR KEY SHARE"
           ) do
        # A remote delete can complete after timeout or replica loss. Fence the
        # key durably before dispatch, even when no publisher has staged it yet.
        # Deleted projects cannot admit another publication and need no fence.
        Repo.insert!(%Publication{project_id: project_id, key: key, intent: %{}, contents: %{}, expired: true})
      end

      keys
    end)
  end

  defp publication_key(key) do
    case String.split(key, "/") do
      [_account, project, "artifacts", key, digest] ->
        with {id, ""} <- Integer.parse(project),
             true <- Package.valid_digest?(key) and Package.valid_digest?(digest) do
          {id, key}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp expired?(_object, %Publication{expired: true}, _cutoff), do: true
  defp expired?(_object, %Publication{}, _cutoff), do: false
  defp expired?(%{last_modified: %DateTime{} = modified}, nil, cutoff), do: DateTime.before?(modified, cutoff)

  defp expired?(%{last_modified: modified}, nil, cutoff) when is_binary(modified) do
    case DateTime.from_iso8601(modified) do
      {:ok, modified, _} -> DateTime.before?(modified, cutoff)
      _ -> false
    end
  end

  defp expired?(_, nil, _), do: false
end
