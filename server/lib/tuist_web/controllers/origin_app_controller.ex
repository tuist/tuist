defmodule TuistWeb.OriginAppController do
  @moduledoc "Verifies Origin approval and requires an explicit Tuist account confirmation."
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Environment
  alias Tuist.Origin
  alias Tuist.Origin.RunnerCheckout

  def runner_credentials(conn, %{"repo_url" => remote}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, access_token} <- RunnerCheckout.credentials(token, remote) do
      json(conn, %{token: access_token})
    else
      {:error, :unavailable} -> conn |> put_status(:service_unavailable) |> json(%{error: "Origin is unavailable"})
      _ -> conn |> put_status(:forbidden) |> json(%{error: "Checkout is not authorized"})
    end
  end

  def runner_credentials(conn, _), do: send_resp(conn, 400, "Repository URL is required.")

  def install(conn, %{"account_id" => account_id}) do
    with user when not is_nil(user) <- conn.assigns.current_user,
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         :ok <- Authorization.authorize(:account_update, user, account),
         %{} <- Environment.origin_app_credentials() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      conn
      |> put_session(:origin_install_state, %{"nonce" => state, "account_name" => account.name})
      |> redirect(external: Origin.install_url(state))
    else
      _ -> send_resp(conn, 403, "Origin installation is not available for this account.")
    end
  end

  def setup(conn, %{"installation_receipt" => receipt}) do
    with {:ok, pending} <- Origin.pending_installation(receipt),
         true <- valid_state?(pending["state"], get_session(conn, :origin_install_state)) do
      conn
      |> put_session(:pending_origin, pending)
      |> put_session(:origin_account_name, get_in(get_session(conn, :origin_install_state) || %{}, ["account_name"]))
      |> delete_session(:origin_install_state)
      |> put_resp_header("referrer-policy", "no-referrer")
      |> redirect(to: ~p"/integrations/origin/continue")
    else
      _ -> conn |> delete_session(:pending_origin) |> send_resp(400, "Invalid or expired Origin installation approval.")
    end
  end

  def setup(conn, _), do: send_resp(conn, 400, "Origin installation approval is required.")

  def continue(conn, _) do
    if user = conn.assigns.current_user do
      account_name = get_session(conn, :origin_account_name) || user.account.name
      redirect(conn, to: "/#{account_name}/settings/integrations")
    else
      conn
      |> put_session(:user_return_to, "/integrations/origin/continue")
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def connect(conn, %{"account_id" => account_id}) do
    with user when not is_nil(user) <- conn.assigns.current_user,
         {:ok, account} <- Accounts.get_account_by_id(account_id),
         {:ok, _} <- Origin.confirm(account, user, get_session(conn, :pending_origin)) do
      conn
      |> delete_session(:pending_origin)
      |> delete_session(:origin_account_name)
      |> redirect(to: "/#{account.name}/settings/integrations")
    else
      _ -> send_resp(conn, 403, "Unable to connect Origin. Check account permissions or install again.")
    end
  end

  defp valid_state?(nil, nil), do: true
  defp valid_state?(nonce, %{"nonce" => nonce}) when is_binary(nonce), do: true
  defp valid_state?(_, _), do: false
end
