defmodule Tuist.Atlas.Email do
  @moduledoc """
  Client for the email API in Atlas, which owns the newsletter audience and the
  transactional email Tuist sends.

  Atlas exposes the same request and response shapes Loops did, so the payloads
  here are unchanged from the Loops client this replaces. Only the base URL and
  the API key differ, both configured through `Tuist.Environment`.

  The verification token and the confirmation pages stay in this app. Atlas only
  renders and delivers the email, and receives the contact once the address is
  verified.
  """

  alias Tuist.Environment

  @transactional_path "/api/email/transactional"
  @contacts_path "/api/email/contacts/update"

  # Atlas addresses templates and audiences by name rather than by the opaque
  # ids Loops generated. It still accepts the old Loops ids as aliases.
  @newsletter_confirmation_template "newsletter-confirmation"
  @newsletter_audience "tuist-digest"

  @doc """
  Sends a transactional email.

  ## Parameters
  - `email`: The recipient email address
  - `transactional_id`: The template to render
  - `data_variables`: Map of variables to fill the template in

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def send_transactional_email(email, transactional_id, data_variables \\ %{}) do
    post(@transactional_path, %{
      "email" => email,
      "transactionalId" => transactional_id,
      "dataVariables" => data_variables
    })
  end

  @doc """
  Adds or updates a contact and its audience subscriptions.

  ## Parameters
  - `email`: The contact email address
  - `mailing_lists`: Map of audience identifiers to boolean subscription status

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def update_contact(email, mailing_lists \\ %{}) do
    post(@contacts_path, %{"email" => email, "mailingLists" => mailing_lists})
  end

  @doc """
  Sends the newsletter confirmation email with the verification URL this app
  generated.
  """
  def send_newsletter_confirmation(email, verification_url) do
    send_transactional_email(email, @newsletter_confirmation_template, %{
      "verificationUrl" => verification_url
    })
  end

  @doc """
  Subscribes an email to the Tuist Digest newsletter audience.
  """
  def add_to_newsletter_list(email) do
    update_contact(email, %{@newsletter_audience => true})
  end

  defp post(path, body) do
    with {:ok, base_url} <- fetch_config(Environment.atlas_email_api_url()),
         {:ok, api_key} <- fetch_config(Environment.atlas_email_api_key()) do
      base_url
      |> URI.merge(path)
      |> URI.to_string()
      |> Req.post(json: body, headers: [{"Authorization", "Bearer #{api_key}"}])
      |> case do
        {:ok, %{status: 200}} -> :ok
        {:ok, %{status: status, body: response_body}} -> {:error, {:http_error, status, response_body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_config(value) when is_binary(value) and value != "", do: {:ok, value}
  defp fetch_config(_value), do: {:error, :not_configured}
end
