defmodule Tuist.GitHubStateToken do
  @moduledoc """
  Manages secure JWT state tokens for GitHub App installation flow.

  State tokens are account IDs signed with the server's secret key using Phoenix.Token.
  Only this server can generate and verify valid state tokens, preventing
  malicious actors from forging installation requests.

  Tokens expire after 90 days to handle extended admin approval processes.
  """

  # 90 days
  @token_max_age_seconds 7_776_000

  @doc """
  Generates a JWT state token for the given account ID.
  Returns the signed token string that should be used in the GitHub installation URL.
  """
  def generate_token(account_id) do
    Phoenix.Token.sign(TuistWeb.Endpoint, "github_state", account_id)
  end

  @doc """
  Verifies the JWT state token to extract the account ID.
  Returns {:ok, account_id} if valid, {:error, reason} if invalid or expired.
  """
  def verify_token(token) do
    Phoenix.Token.verify(TuistWeb.Endpoint, "github_state", token, max_age: @token_max_age_seconds)
  end
end
