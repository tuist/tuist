defmodule TuistWeb.Internal.AtlasUsageController do
  @moduledoc """
  Internal Atlas read model endpoints.

  Atlas authenticates with its projected Kubernetes ServiceAccount token. Tuist
  validates the token with TokenReview and then gates the principal to the
  configured Atlas namespace and ServiceAccount.
  """

  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient

  require Logger

  def usage(conn, %{"account_handle" => account_handle}) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, principal} <- K8sClient.create_atlas_token_review(token),
         :ok <- ensure_atlas_principal(principal),
         %Account{} = account <- Accounts.get_account_by_handle(account_handle) do
      json(conn, %{
        current_month_remote_cache_hits: account.current_month_remote_cache_hits_count
      })
    else
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "account_not_found"})

      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing bearer token"})

      {:error, :unauthenticated} ->
        Logger.warning("atlas: tokenreview rejected token")
        conn |> put_status(:unauthorized) |> json(%{error: "invalid token"})

      {:error, :not_service_account} ->
        Logger.warning("atlas: tokenreview principal is not an SA")
        conn |> put_status(:unauthorized) |> json(%{error: "not a service account"})

      {:error, {:wrong_principal, %{namespace: ns, name: name}}} ->
        Logger.warning("atlas: unauthorized principal",
          principal_namespace: ns,
          principal_name: name
        )

        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized principal"})

      {:error, :not_in_cluster} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "kubernetes unavailable"})

      {:error, reason} ->
        Logger.error("atlas: usage lookup failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "usage lookup failed"})
    end
  end

  defp ensure_atlas_principal(%{namespace: namespace, name: name} = principal) do
    if namespace == Environment.atlas_namespace() and name == Environment.atlas_service_account_name() do
      :ok
    else
      {:error, {:wrong_principal, principal}}
    end
  end

  defp bearer_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end
end
