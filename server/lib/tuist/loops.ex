defmodule Tuist.Loops do
  @moduledoc """
  Interface for interacting with the Loops.so API for email campaigns and contact management.
  """

  alias Tuist.Environment

  @doc """
  Sends a transactional email campaign via Loops.

  ## Parameters
  - `email`: The recipient email address
  - `transactional_id`: The Loops transactional campaign ID
  - `data_variables`: Map of variables to pass to the email template

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def send_transactional_email(email, transactional_id, data_variables \\ %{}) do
    api_key = Environment.loops_api_key()

    body = %{
      "email" => email,
      "transactionalId" => transactional_id,
      "dataVariables" => data_variables
    }

    case Req.post("https://app.loops.so/api/v1/transactional",
           json: body,
           headers: [{"Authorization", "Bearer #{api_key}"}]
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status_code, body: response_body}} ->
        {:error, {:http_error, status_code, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds or updates a contact in Loops and subscribes them to mailing lists.

  ## Parameters
  - `email`: The contact email address
  - `mailing_lists`: Map of mailing list IDs to boolean subscription status

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def update_contact(email, mailing_lists \\ %{}) do
    api_key = Environment.loops_api_key()

    body = %{
      "email" => email,
      "mailingLists" => mailing_lists
    }

    case Req.post("https://app.loops.so/api/v1/contacts/update",
           json: body,
           headers: [{"Authorization", "Bearer #{api_key}"}]
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status_code}} ->
        {:error, {:http_error, status_code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a newsletter confirmation email with verification URL.

  ## Parameters
  - `email`: The email address to send confirmation to
  - `verification_url`: URL for the user to verify their subscription

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def send_newsletter_confirmation(email, verification_url) do
    send_transactional_email(email, "cmfglb1pe5esq2w0ixnkdou94", %{
      "verificationUrl" => verification_url
    })
  end

  @doc """
  Adds an email to the Tuist Digest newsletter mailing list.

  ## Parameters
  - `email`: The email address to subscribe

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def add_to_newsletter_list(email) do
    update_contact(email, %{
      "cmfgl9s214xcv0izt5jyu7e9d" => true
    })
  end

  @doc """
  Adds an email to the QA waiting list.

  ## Parameters
  - `email`: The email address to add to the waiting list

  ## Returns
  - `:ok` on success
  - `{:error, reason}` on failure
  """
  def add_to_qa_waiting_list(email) do
    update_contact(email, %{
      "cmfo87vbh457g0i04bp15gs5s" => true
    })
  end
end
