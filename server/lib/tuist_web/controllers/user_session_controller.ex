defmodule TuistWeb.UserSessionController do
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Environment
  alias TuistWeb.Authentication

  require Logger

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
    if Environment.email_auth_enabled?() do
      rate_limited_create(conn, params, info)
    else
      conn
      |> put_flash(:error, "Email and password sign-in is disabled.")
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  defp rate_limited_create(conn, params, info) do
    case TuistWeb.RateLimit.Auth.hit(conn) do
      {:allow, _count} ->
        do_create(conn, params, info)

      {:deny, _limit} ->
        log_authentication_outcome("rate_limited")

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
        log_authentication_outcome("success")

        conn
        |> put_flash(:info, info)
        |> Authentication.log_in_user(user, user_params)

      {:error, :invalid_email_or_password} ->
        log_authentication_outcome("invalid_credentials")

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:email, email)
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/users/log_in")
        |> halt()

      {:error, :not_confirmed} ->
        log_authentication_outcome("unconfirmed")

        # Valid credentials but an unconfirmed email. The password already proved
        # ownership, so carry the email to the resend page for a one-click resend
        # instead of dead-ending on the login form.
        conn
        |> put_session(:unconfirmed_email, email)
        |> redirect(to: ~p"/users/confirm")
        |> halt()
    end
  end

  # Every outcome of a sign-in attempt redirects, successes and failures alike,
  # so the response status cannot tell them apart. Reviewing authentication
  # needs an explicit outcome to count, which is what this emits. The acting
  # address is already on the record from the observability context.
  defp log_authentication_outcome(outcome) do
    Logger.info("authentication attempt", auth_outcome: outcome)
  end

  def new(conn, %{"return_to" => "//" <> _}) do
    redirect(conn, to: ~p"/users/log_in")
  end

  def new(conn, %{"return_to" => "/" <> _ = return_to}) do
    conn
    |> put_session(:user_return_to, return_to)
    |> redirect(to: ~p"/users/log_in?#{%{return_to: return_to}}")
  end

  def new(conn, _params) do
    redirect(conn, to: ~p"/users/log_in")
  end

  def delete(conn, %{"return_to" => "//" <> _}) do
    Authentication.log_out_user(conn)
  end

  def delete(conn, %{"return_to" => "/" <> _ = return_to}) do
    Authentication.log_out_user(conn, return_to: return_to)
  end

  def delete(conn, _params) do
    Authentication.log_out_user(conn)
  end
end
