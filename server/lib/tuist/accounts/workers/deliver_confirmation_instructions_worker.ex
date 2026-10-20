defmodule Tuist.Accounts.Workers.DeliverConfirmationInstructionsWorker do
  @moduledoc """
  Delivers a user confirmation email outside the registration request.

  The confirmation URL is encrypted before it is persisted in the job arguments,
  so the token remains protected while Oban retries a transient delivery failure.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Repo

  @confirmation_url_salt "confirmation-instructions-url"
  @confirmation_url_max_age_seconds 7 * 24 * 60 * 60

  def new_confirmation_instructions(user_id, confirmation_url) do
    new(%{user_id: user_id, encrypted_confirmation_url: encrypt_confirmation_url(confirmation_url)})
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "encrypted_confirmation_url" => encrypted_confirmation_url}}) do
    with %User{} = user <- Repo.get(User, user_id),
         {:ok, confirmation_url} <- decrypt_confirmation_url(encrypted_confirmation_url),
         {:ok, _email} <-
           UserNotifier.deliver_confirmation_instructions(%{
             user: user,
             confirmation_url: confirmation_url
           }) do
      :ok
    else
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp encrypt_confirmation_url(confirmation_url) do
    Phoenix.Token.encrypt(TuistWeb.Endpoint, @confirmation_url_salt, confirmation_url)
  end

  defp decrypt_confirmation_url(encrypted_confirmation_url) do
    Phoenix.Token.decrypt(TuistWeb.Endpoint, @confirmation_url_salt, encrypted_confirmation_url,
      max_age: @confirmation_url_max_age_seconds
    )
  end
end
