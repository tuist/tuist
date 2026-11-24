defmodule Tuist.Push.LiveActivities do
  @moduledoc """
  Generic ActivityKit token registry and APNs transport for Luft. Tuist never
  reads conversations or constructs their content. The authenticated Luft user
  may address only tokens registered under that exact upstream OAuth lineage.
  """
  import Ecto.Query

  alias Tuist.Accounts.User
  alias Tuist.Push
  alias Tuist.Push.APNs
  alias Tuist.Push.LiveActivity
  alias Tuist.Push.LiveActivityStarter
  alias Tuist.Repo

  @token ~r/\A(?:[0-9a-fA-F]{2}){16,256}\z/
  @profile ~r/\A[A-Za-z0-9_-]{1,128}\z/
  @lifetime 8 * 60 * 60
  @batch 1000
  def version, do: 1
  def prune_batch_size, do: @batch

  def register(%User{} = user, %{app: "luft", oauth_grant_id: grant}, id, params) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, token, environment} <- params(params),
         true <- Push.grant_active?("luft", grant, user.id) do
      locked("activity:" <> id, user.id, fn ->
        case Repo.get(LiveActivity, id) do
          %LiveActivity{retired_at: retired} when not is_nil(retired) ->
            {:error, :retired}

          %LiveActivity{user_id: owner, oauth_grant_id: existing} when owner != user.id or existing != grant ->
            {:error, :conflict}

          %LiveActivity{} = registration ->
            save(registration, user, grant, token, environment)

          nil ->
            LiveActivity
            |> where([a], a.user_id == ^user.id and a.oauth_grant_id == ^grant and is_nil(a.retired_at))
            |> Repo.update_all(set: retired("replaced"))

            save(%LiveActivity{id: id, expires_at: DateTime.add(now(), @lifetime)}, user, grant, token, environment)
        end
      end)
    else
      _ -> {:error, :invalid}
    end
  end

  def register(_, _, _, _), do: {:error, :invalid}

  def unregister(%User{} = user, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        locked("activity:" <> id, user.id, fn ->
          case Repo.get(LiveActivity, id) do
            nil -> Repo.insert!(struct(LiveActivity, [id: id, expires_at: now()] ++ retired("unregistered")))
            %LiveActivity{user_id: owner, retired_at: nil} = row when owner == user.id -> retire(row, "unregistered")
            _ -> :ok
          end

          :ok
        end)

      _ ->
        {:error, :invalid}
    end
  end

  def register_starter(%User{} = user, %{app: "luft", oauth_grant_id: grant}, input) do
    with {:ok, token, environment} <- params(input),
         profile when is_binary(profile) <- input["profile_id"],
         true <- Regex.match?(@profile, profile),
         true <- Push.grant_active?("luft", grant, user.id) do
      hash = LiveActivityStarter.token_hash(token)

      locked("starter:" <> Base.encode16(hash), user.id, fn ->
        LiveActivityStarter |> where([s], s.token_hash == ^hash and s.oauth_grant_id != ^grant) |> Repo.delete_all()

        Repo.insert!(
          %LiveActivityStarter{
            user_id: user.id,
            oauth_grant_id: grant,
            token: token,
            token_hash: hash,
            environment: environment,
            profile_id: profile
          },
          on_conflict: {:replace, [:profile_id, :environment, :token, :token_hash, :updated_at]},
          conflict_target: :oauth_grant_id
        )

        :ok
      end)
    else
      _ -> {:error, :invalid}
    end
  end

  def register_starter(_, _, _), do: {:error, :invalid}

  def unregister_starter(%User{} = user, %{oauth_grant_id: grant}) do
    LiveActivityStarter |> where([s], s.user_id == ^user.id and s.oauth_grant_id == ^grant) |> Repo.delete_all()
    :ok
  end

  # Retained only for old jobs/callers during the rolling migration. No source
  # conversation reads or projection work can run through these entry points.
  def thread_changed(_), do: :ok
  def deliver(_), do: :done
  def start(_), do: :ok
  def schedule_heartbeat(_), do: :ok

  def dispatch(%User{} = user, %{app: "luft", oauth_grant_id: grant}, input) do
    with {:ok, token, environment} <- params(input),
         %{"aps" => aps} = payload <- input["payload"],
         true <- is_map(aps) and byte_size(JSON.encode!(payload)) <= 4096,
         %{"event" => event, "timestamp" => timestamp} <- aps,
         true <- event in ["start", "update", "end"] and is_integer(timestamp),
         true <- Push.grant_active?("luft", grant, user.id),
         :ok <- authorize_token(user.id, grant, token, environment, event),
         {:ok, options} <- options(input["options"] || %{}) do
      APNs.deliver(environment, token, payload, "dev.tuist.code.push-type.liveactivity", options)
    else
      {:error, :invalid_token} -> {:error, :invalid_token}
      _ -> {:error, :invalid}
    end
  end

  def dispatch(_, _, _), do: {:error, :invalid}

  defp authorize_token(user, grant, token, environment, event) do
    if owns_token?(user, grant, token, environment, event), do: :ok, else: {:error, :invalid_token}
  end

  defp owns_token?(user, grant, token, environment, "start") do
    hash = LiveActivityStarter.token_hash(token)

    Repo.exists?(
      from s in LiveActivityStarter,
        where:
          s.user_id == ^user and s.oauth_grant_id == ^grant and s.token_hash == ^hash and s.environment == ^environment
    )
  end

  defp owns_token?(user, grant, token, environment, _) do
    hash = LiveActivity.token_hash(token)

    Repo.exists?(
      from a in LiveActivity,
        where:
          a.user_id == ^user and a.oauth_grant_id == ^grant and a.token_hash == ^hash and
            a.environment == ^environment and is_nil(a.retired_at) and a.expires_at > ^now()
    )
  end

  defp options(%{"priority" => priority, "expiration" => expiration} = options)
       when priority in [5, 10] and is_integer(expiration) do
    base = [push_type: "liveactivity", priority: priority, expiration: expiration]

    case options["collapse_id"] do
      nil -> {:ok, base}
      value when is_binary(value) and byte_size(value) <= 64 -> {:ok, Keyword.put(base, :collapse_id, value)}
      _ -> {:error, :invalid}
    end
  end

  defp options(_), do: {:error, :invalid}

  def prune do
    expired = from a in LiveActivity, where: is_nil(a.retired_at) and a.expires_at <= ^now(), limit: @batch, select: a.id
    {retired, _} = Repo.update_all(from(a in LiveActivity, where: a.id in subquery(expired)), set: retired("expired"))
    old = from a in LiveActivity, where: a.retired_at < ^DateTime.add(now(), -180, :day), limit: @batch, select: a.id
    {deleted, _} = Repo.delete_all(from a in LiveActivity, where: a.id in subquery(old))

    stale =
      from s in LiveActivityStarter, where: s.updated_at < ^DateTime.add(now(), -60, :day), limit: @batch, select: s.id

    {starters, _} = Repo.delete_all(from s in LiveActivityStarter, where: s.id in subquery(stale))
    %{retired: retired, deleted: deleted, starters: starters}
  end

  defp save(row, user, grant, token, environment) do
    hash = LiveActivity.token_hash(token)

    LiveActivity
    |> where([a], a.token_hash == ^hash and a.id != ^row.id and is_nil(a.retired_at))
    |> Repo.update_all(set: retired("superseded"))

    saved =
      row
      |> Ecto.Changeset.change(
        user_id: user.id,
        oauth_grant_id: grant,
        token: token,
        token_hash: hash,
        environment: environment
      )
      |> Repo.insert_or_update!()

    keep =
      from a in LiveActivity,
        where: a.user_id == ^user.id and is_nil(a.retired_at),
        order_by: [desc: a.inserted_at, desc: a.id],
        limit: 10,
        select: a.id

    LiveActivity
    |> where([a], a.user_id == ^user.id and is_nil(a.retired_at) and a.id not in subquery(keep))
    |> Repo.update_all(set: retired("evicted"))

    {:ok, saved}
  end

  defp retire(row, reason), do: row |> Ecto.Changeset.change(retired(reason)) |> Repo.update!()

  defp retired(reason),
    do: [
      retired_at: now(),
      retired_reason: reason,
      user_id: nil,
      oauth_grant_id: nil,
      token: nil,
      token_hash: nil,
      last_digest: nil,
      last_phase_digest: nil,
      working_thread_ids: []
    ]

  defp now, do: DateTime.utc_now(:second)

  defp locked(key, user, fun) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["activity-user:#{user}"])
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])
        fun.()
      end)

    result
  end

  defp params(%{"token" => token, "environment" => environment})
       when is_binary(token) and environment in ["sandbox", "production"] do
    if Regex.match?(@token, token), do: {:ok, String.downcase(token), environment}, else: {:error, :invalid}
  end

  defp params(_), do: {:error, :invalid}
end
