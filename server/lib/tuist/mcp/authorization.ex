defmodule Tuist.MCP.Authorization do
  @moduledoc false

  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authorization

  def authorize(subject, action, resource, category) do
    Authorization.authorize(:"#{category}_#{action}", subject, resource) == :ok
  end

  @doc """
  Authorize a request from its assigns, consulting an operator grant when the
  authenticated subject alone is not enough.

  An OAuth-token session authorizes as the `AuthenticatedAccount` the token's
  scopes hang off, which is why that subject decides first — and why it must keep
  deciding for anything that writes. An operator grant belongs to the human
  behind the token rather than to the token, so it is consulted only after the
  subject was refused, and only for reads: a grant widens *which* accounts are
  visible, never what the credential is allowed to do.
  """
  def authorize_request(assigns, action, resource, category) when is_map(assigns) do
    authorize(authenticated_subject(assigns), action, resource, category) or
      operator_grant_authorizes_read?(assigns, action, resource, category)
  end

  # `:operator_grant_user` is where `TuistWeb.OperatorGrant` puts the human it
  # resolved and verified the grant for — the token's own subject stays whatever
  # authenticated. `:current_user` covers the browser and claimed-agent sessions
  # that carry the grant on the user directly.
  defp operator_grant_authorizes_read?(assigns, :read, resource, category) do
    with true <- mcp_scoped?(authenticated_subject(assigns)),
         %User{operator_grant: grant} = user when is_map(grant) <-
           assigns[:operator_grant_user] || assigns[:current_user] do
      authorize(user, :read, resource, category)
    else
      _ -> false
    end
  end

  defp operator_grant_authorizes_read?(_assigns, _action, _resource, _category), do: false

  # The endpoint asks only that a credential authenticated, so without this the
  # grant would hand customer reads to a token scoped for something else
  # entirely — widening what the credential may do, which is exactly what the
  # grant is not for. Presets expand outwards (`mcp` to its members, never the
  # reverse), so an unrelated read scope cannot satisfy this by accident.
  #
  # A `User` subject is a session rather than a scoped credential: there is no
  # narrower thing for it to have been restricted to, and the grant checks still
  # require it to be the operator the grant names.
  defp mcp_scoped?(%AuthenticatedAccount{scopes: scopes}) when is_list(scopes) do
    AccountToken.mcp_scope() in scopes
  end

  defp mcp_scoped?(%User{}), do: true
  defp mcp_scoped?(_subject), do: false

  def authenticated_subject(assigns) when is_map(assigns) do
    assigns[:current_subject] || assigns[:current_user] || assigns[:current_project]
  end
end
