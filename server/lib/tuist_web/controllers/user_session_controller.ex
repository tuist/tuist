defmodule TuistWeb.UserSessionController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias TuistWeb.Authentication

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

  defp create(conn, params, info) do
    case TuistWeb.RateLimit.Auth.hit(conn) do
      {:allow, _count} ->
        do_create(conn, params, info)

      {:deny, _limit} ->
        conn
        |> put_flash(:error, dgettext("dashboard", "You've exceeded the rate limit. Try again later."))
        |> redirect(to: ~p"/users/log_in")
        |> halt()
    end
  end

  defp do_create(conn, params, info) do
    user_params =
      %{"email" => email, "password" => password} =
      if Map.has_key?(params, "user") do
        params["user"]
      else
        %{
          "email" => params["user[email]"],
          "password" => params["user[password]"],
          "remember_me" => params["user[remember_me]"]
        }
      end

    email = String.trim(email)

    case Accounts.get_user_by_email_and_password(email, password) do
      {:ok, user} ->
        conn
        |> put_flash(:info, info)
        |> Authentication.log_in_user(user, user_params)

      {:error, :invalid_email_or_password} ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:email, email)
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/users/log_in")
        |> halt()

      {:error, :not_confirmed} ->
        conn
        |> put_flash(:error, "Please confirm your account before logging in.")
        |> redirect(to: ~p"/users/log_in")
        |> halt()
    end
  end

  def delete(conn, _params) do
    Authentication.log_out_user(conn)
  end
end
