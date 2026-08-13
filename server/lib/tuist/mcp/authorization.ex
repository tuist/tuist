defmodule Tuist.MCP.Authorization do
  @moduledoc false

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

  defp operator_grant_authorizes_read?(assigns, :read, resource, category) do
    case assigns[:current_user] do
      %User{operator_grant: grant} = user when is_map(grant) ->
        authorize(user, :read, resource, category)

      _ ->
        false
    end
  end

  defp operator_grant_authorizes_read?(_assigns, _action, _resource, _category), do: false

  def authenticated_subject(assigns) when is_map(assigns) do
    assigns[:current_subject] || assigns[:current_user] || assigns[:current_project]
  end
end
