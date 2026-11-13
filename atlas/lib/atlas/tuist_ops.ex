defmodule Atlas.TuistOps do
  @moduledoc """
  Client for tuist-ops (`ops.tuist.dev`), which owns cluster elevations.

  Atlas authenticates with a projected ServiceAccount token for the
  `ops.tuist.dev` audience, read fresh from disk on each call because the
  kubelet rotates it in place. tuist-ops verifies it offline against the
  Atlas cluster's pinned JWKS, then trusts Atlas for who approved the call.
  Calls never retry: a failed grant needs a new approval.
  """

  require Logger

  @doc """
  `:ok` when this environment can reach tuist-ops (its token file is mounted),
  so a tool can refuse before asking anyone to approve a call that cannot run.
  """
  def configured do
    with {:ok, _token} <- read_token(__MODULE__.config()[:token_path]), do: :ok
  end

  @doc """
  Grants an orb thread write access to a cluster env after `email` approved
  the call in Atlas. `attrs` carries `env`, `thread_id`, `intent`,
  `ttl_seconds` and `approval_id`.
  """
  def grant_thread_elevation(email, attrs) when is_binary(email) and is_map(attrs) do
    config = __MODULE__.config()

    with {:ok, token} <- read_token(config[:token_path]) do
      request =
        Req.request(
          method: :post,
          url: String.trim_trailing(config[:base_url] || "", "/") <> "/api/v1/atlas/elevations",
          auth: {:bearer, token},
          json: Map.put(attrs, "email", email),
          retry: false
        )

      case request do
        {:ok, %Req.Response{status: 201, body: body}} ->
          {:ok, body}

        {:ok, %Req.Response{status: status, body: %{"error" => error}}} ->
          Logger.warning("tuist-ops elevation grant failed: status=#{status}")
          {:error, "tuist-ops refused the elevation (HTTP #{status}): #{error}"}

        {:ok, %Req.Response{status: status}} ->
          Logger.warning("tuist-ops elevation grant failed: status=#{status}")
          {:error, "tuist-ops returned HTTP #{status}."}

        {:error, _reason} ->
          Logger.warning("tuist-ops elevation grant transport error")
          {:error, "Could not reach tuist-ops."}
      end
    end
  end

  defp read_token(path) when is_binary(path) and path != "" do
    case File.read(path) do
      {:ok, contents} when contents != "" -> {:ok, String.trim(contents)}
      _ -> {:error, "Cluster elevations are not configured in this Atlas environment."}
    end
  end

  defp read_token(_path), do: {:error, "Cluster elevations are not configured in this Atlas environment."}

  @doc false
  # Public so tests can stub it with Mimic instead of mutating app config.
  def config, do: Application.get_env(:atlas, :tuist_ops, [])
end
