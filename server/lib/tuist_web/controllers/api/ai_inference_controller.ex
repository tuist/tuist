defmodule TuistWeb.API.AIInferenceController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Accounts.AISubscriptions.Inference
  alias Tuist.Accounts.User
  alias Tuist.FeatureFlags
  alias TuistWeb.Authentication

  def models(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case admitted_user(conn) do
      {:ok, user} -> json(conn, Inference.models(user, fn -> authorized?(conn, user.id) end))
      {:error, status, category} -> error(conn, status, category)
    end
  end

  def complete(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with {:ok, user} <- admitted_user(conn),
         {:ok, completion} <-
           Inference.personal_completion(user, conn.body_params, fn -> authorized?(conn, user.id) end) do
      json(conn, completion)
    else
      {:error, status, category} -> error(conn, status, category)
    end
  end

  # app_user revalidates the first-party client or configured Luft server's
  # active luft:app grant. Reload the user too: the authenticated subject may
  # contain a snapshot from before deactivation. Repeat after credential refresh.
  defp admitted_user(conn) do
    with %User{id: id} <- Authentication.app_user(conn),
         %User{active: true, disabled_at: nil} = user <- Accounts.get_user_by_id(id),
         true <- FeatureFlags.luft_enabled?(user) do
      {:ok, user}
    else
      nil -> {:error, 403, :forbidden}
      _ -> {:error, 404, :not_found}
    end
  end

  defp authorized?(conn, id), do: match?({:ok, %User{id: ^id}}, admitted_user(conn))

  defp error(conn, status, category) do
    conn
    |> put_status(status)
    |> json(%{
      error: %{
        message: "The assistant's inference provider is unavailable.",
        type: "provider_error",
        code: Atom.to_string(category)
      }
    })
  end
end
