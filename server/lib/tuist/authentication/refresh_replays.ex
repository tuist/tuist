defmodule Tuist.Authentication.RefreshReplays do
  @moduledoc """
  Makes refresh-token exchanges replayable for a short window.

  A client whose refresh response was lost retries with the refresh token it
  already spent. For 60 seconds after a successful exchange, presenting the
  same token (with the same client credentials, when the caller passes them)
  returns the response the first exchange returned instead of being rejected.
  After the window the token is rejected as before.

  Exchanges of one token are serialized across replicas with a PostgreSQL
  advisory lock, so concurrent duplicates mint a single pair. Entries are
  keyed by a SHA-256 digest of the token, never the token itself, and the
  stored response is encrypted with `Tuist.Vault`.
  """

  import Ecto.Query

  alias Tuist.Authentication.RefreshReplays.Replay
  alias Tuist.Repo

  @window_seconds 60

  def window_seconds, do: @window_seconds

  @doc """
  Runs `exchange` for `refresh_token` unless a response for the same token and
  credential was recorded within the window, in which case that response is
  returned as `{:ok, response}` with string keys. `exchange` returns
  `{:ok, response}` for a response map that is recorded, or anything else,
  which is returned without being recorded.
  """
  def exchange(kind, refresh_token, credential \\ nil, exchange) when is_binary(kind) and is_binary(refresh_token) do
    token_hash = digest(refresh_token)
    credential_hash = if is_nil(credential), do: nil, else: digest(credential)

    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
          "refresh_replay:#{kind}:#{Base.encode16(token_hash)}"
        ])

        case recorded_response(kind, token_hash, credential_hash) do
          nil -> exchange_and_record(kind, token_hash, credential_hash, exchange)
          response -> {:ok, response}
        end
      end)

    result
  end

  @doc """
  Deletes expired entries and returns how many were deleted.
  """
  def prune do
    now = Tuist.Time.utc_now()
    {deleted, _} = Repo.delete_all(from(replay in Replay, where: replay.expires_at <= ^now))
    deleted
  end

  defp recorded_response(kind, token_hash, credential_hash) do
    now = Tuist.Time.utc_now()

    from(replay in Replay,
      where: replay.kind == ^kind and replay.token_hash == ^token_hash and replay.expires_at > ^now
    )
    |> Repo.one()
    |> case do
      %Replay{credential_hash: ^credential_hash, response: response} -> JSON.decode!(response)
      _ -> nil
    end
  end

  defp exchange_and_record(kind, token_hash, credential_hash, exchange) do
    case exchange.() do
      {:ok, response} = result when is_map(response) ->
        now = DateTime.truncate(Tuist.Time.utc_now(), :second)

        Repo.insert!(
          %Replay{
            kind: kind,
            token_hash: token_hash,
            credential_hash: credential_hash,
            response: JSON.encode!(response),
            expires_at: DateTime.add(now, @window_seconds, :second),
            inserted_at: now
          },
          on_conflict: {:replace, [:credential_hash, :response, :expires_at, :inserted_at]},
          conflict_target: [:kind, :token_hash]
        )

        result

      other ->
        other
    end
  end

  defp digest(value), do: :crypto.hash(:sha256, value)
end
