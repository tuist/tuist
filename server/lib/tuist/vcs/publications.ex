defmodule Tuist.VCS.Publications do
  @moduledoc """
  Durable single-attempt publication broker. The insert commits authorization
  BEFORE any GitHub write. That authorization cannot be revoked by a remote
  caller's lease expiring: it is the explicit distributed commit point, not an
  imitation of a cross-database transaction. A replay only observes GitHub.
  Even a crash before the first write leaves an uncertain record, never a
  retryable write. No absence observation proves an in-flight write cannot land.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.VCS.Publication
  alias Tuist.VCS.RepositoryBroker

  def publish(account, user, request_id, snapshot, objects, diff) do
    fingerprint = :crypto.hash(:sha256, JSON.encode!(%{snapshot: snapshot, objects: objects, diff: diff, user: user.id}))
    existing = Repo.get_by(Publication, account_id: account.id, request_id: request_id)

    if existing do
      replay(account, user, existing, fingerprint)
    else
      with {:ok, _} <- RepositoryBroker.authorize(account, user, snapshot.repository, :write),
           {:ok, ^diff} <- RepositoryBroker.review(account, snapshot, objects) do
        reserve(account, user, request_id, snapshot, objects, fingerprint)
      else
        {:ok, _} -> {:error, :shipping_review_stale}
        error -> error
      end
    end
  end

  defp reserve(account, user, request_id, snapshot, objects, fingerprint) do
    attrs = Map.take(snapshot, [:repository, :target_branch, :base_sha, :head_sha, :mode])

    operation =
      struct!(
        Publication,
        Map.merge(attrs, %{
          account_id: account.id,
          user_id: user.id,
          request_id: request_id,
          operation_id: snapshot.thread_id,
          fingerprint: fingerprint,
          status: "outcome_unknown"
        })
      )

    # ON CONFLICT coordinates replicas without raising/aborting a surrounding
    # transaction. Only the request which inserted may ever perform a write.
    {:ok, inserted} =
      Repo.insert(operation, on_conflict: :nothing, conflict_target: [:account_id, :request_id], returning: true)

    fresh = Repo.get_by!(Publication, account_id: account.id, request_id: request_id)

    if fresh.id == inserted.id do
      case RepositoryBroker.ship(account, snapshot, fn -> {:ok, objects} end, fn -> :ok end) do
        :ok -> succeeded(fresh)
        _ -> {:error, :shipping_uncertain}
      end
    else
      replay(account, user, fresh, fingerprint)
    end
  end

  defp replay(account, user, publication, fingerprint) do
    if publication.user_id == user.id and publication.fingerprint == fingerprint,
      do: reconcile(account, user, publication.request_id),
      else: {:error, :request_conflict}
  end

  def reconcile(account, user, request_id) do
    with %Publication{user_id: user_id} = publication <-
           Repo.get_by(Publication, account_id: account.id, request_id: request_id),
         true <- user_id == user.id,
         {:ok, _} <- RepositoryBroker.authorize(account, user, publication.repository, :write),
         :ok <- RepositoryBroker.reconcile(account, publication) do
      succeeded(publication)
    else
      _ -> {:error, :shipping_uncertain}
    end
  end

  defp succeeded(publication) do
    Repo.update_all(from(p in Publication, where: p.id == ^publication.id),
      set: [status: "succeeded", updated_at: DateTime.utc_now(:second)]
    )

    {:ok, %{request_id: publication.request_id, head_sha: publication.head_sha, target_branch: publication.target_branch}}
  end
end
