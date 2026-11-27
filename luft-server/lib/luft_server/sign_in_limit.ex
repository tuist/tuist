defmodule LuftServer.SignInLimit do
  @moduledoc """
  Bounds how often a sign-in to a third party starts, before it is called.
  Counts live in `sign_in_limits` under a key naming who started them (a
  person, or the owner of MCP servers), apart from the credentials they
  lead to, so removing those never resets a count. One statement counts and
  checks, so the limit holds across replicas.
  """

  alias LuftServer.Repo

  @doc "Counts an attempt for `key`: `:ok` while within `limit` per `window` seconds."
  def hit(key, limit, window) when is_binary(key) do
    %{rows: [[attempts]]} =
      Repo.query!(
        """
        INSERT INTO sign_in_limits AS l (key, attempts, window_started_at)
        VALUES ($1, 1, now())
        ON CONFLICT (key) DO UPDATE SET
          attempts = CASE WHEN l.window_started_at <= now() - make_interval(secs => $2)
                          THEN 1 ELSE l.attempts + 1 END,
          window_started_at = CASE WHEN l.window_started_at <= now() - make_interval(secs => $2)
                                   THEN now() ELSE l.window_started_at END
        RETURNING attempts
        """,
        [key, window],
        log: false
      )

    if attempts <= limit, do: :ok, else: {:error, :rate_limited}
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :storage_unavailable}
  end
end
