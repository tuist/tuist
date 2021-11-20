defmodule TuistCloudWeb.UserSessionController do
  use TuistCloudWeb, :controller

  alias TuistCloud.Accounts
  alias TuistCloudWeb.Authentication

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, info)
        |> Authentication.log_in_user(user, user_params)

      {:error, :invalid_email_or_password} ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/users/log_in")

      {:error, :not_confirmed} ->
        conn
        |> put_flash(:error, "Please confirm your account before logging in.")
        |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> Authentication.log_out_user()
  end
end
