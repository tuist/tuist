defmodule Tuist.MCP.Authorization do
  @moduledoc false

  alias Tuist.Accounts.AccountToken
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.Authorization
  alias Tuist.Authorization.Checks

  def authorize(subject, action, resource, category) do
    Authorization.authorize(:"#{category}_#{action}", subject, resource) == :ok
  end

  @doc """
  Authorize a request from its assigns.

  An OAuth-token session authenticates as the `AuthenticatedAccount` the token's
  scopes hang off, and that subject decides first. When the authentication plug
  associated the credential with the user who granted or claimed it, the request
  is then authorized as that user, so tools apply the same checks as the
  dashboard. A Tuist operator calling through Atlas is consulted last, and only
  for reads: that elevation belongs to the human behind the token rather than to
  the token, so it widens *which* accounts are visible, never what the credential
  is allowed to do.
  """
  def authorize_request(assigns, action, resource, category) when is_map(assigns) do
    authorize(authenticated_subject(assigns), action, resource, category) or
      associated_user_authorizes?(assigns, action, resource, category) or
      atlas_operator_authorizes_read?(assigns, action, resource, category)
  end

  # `current_user` sits next to an `AuthenticatedAccount` only on the MCP
  # endpoint, for an `mcp`-scoped credential that a user granted or claimed
  # (`TuistWeb.AuthenticationPlug`). The user carries no operator grant here, so
  # this reaches exactly the user's own memberships.
  defp associated_user_authorizes?(
         %{current_subject: %AuthenticatedAccount{}, current_user: %User{} = user},
         action,
         resource,
         category
       ) do
    authorize(user, action, resource, category)
  end

  defp associated_user_authorizes?(_assigns, _action, _resource, _category), do: false

  # `:atlas_operator` is set by `TuistWeb.OperatorGrant.accept_atlas_identity_header/2`
  # for a verified operator calling through Atlas. The operator is given a read
  # grant for the resource's own account, valid for this check only, and then
  # goes through the same policies as a grant from ops in the browser. That keeps operator
  # reads limited to what `:ops_access` already allows.
  defp atlas_operator_authorizes_read?(assigns, :read, resource, category) do
    with true <- mcp_scoped?(authenticated_subject(assigns)),
         %User{email: email} = operator when is_binary(email) <- assigns[:atlas_operator],
         account_id when not is_nil(account_id) <- Checks.object_account_id(resource) do
      grant = %{tier: :read, account_id: account_id, sub: email, exp: System.system_time(:second) + 60}

      if authorize(%{operator | operator_grant: grant}, :read, resource, category) do
        Logger.metadata(atlas_operator_read_account_id: account_id)
        true
      else
        false
      end
    else
      _ -> false
    end
  end

  defp atlas_operator_authorizes_read?(_assigns, _action, _resource, _category), do: false

  # The endpoint asks only that a credential authenticated, so without this the
  # operator elevation would hand customer reads to a token scoped for something
  # else entirely — widening what the credential may do, which is exactly what
  # the elevation is not for. Presets expand outwards (`mcp` to its members,
  # never the reverse), so an unrelated read scope cannot satisfy this by
  # accident.
  #
  # A `User` subject is a session rather than a scoped credential: there is no
  # narrower thing for it to have been restricted to, and the grant checks still
  # require it to be a confirmed operator.
  defp mcp_scoped?(%AuthenticatedAccount{scopes: scopes}) when is_list(scopes) do
    AccountToken.mcp_scope() in scopes
  end

  defp mcp_scoped?(%User{}), do: true
  defp mcp_scoped?(_subject), do: false

  def authenticated_subject(assigns) when is_map(assigns) do
    assigns[:current_subject] || assigns[:current_user] || assigns[:current_project]
  end
end
