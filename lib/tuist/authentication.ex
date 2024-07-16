defmodule Tuist.Authentication do
  @moduledoc ~S"""
  A module to deal with authentication in the system.
  """
  alias Tuist.Projects
  alias Tuist.Accounts

  def authenticated_subject(token) do
    case Tuist.Guardian.resource_from_token(token) do
      {:ok, resource, _opts} ->
        resource

      _ ->
        user = Accounts.get_user_by_token(token)

        if is_nil(user) do
          Projects.get_project_by_full_token(token)
        else
          user
        end
    end
  end

  def refresh(token, opts) do
    Tuist.Guardian.refresh(token, opts)
  end

  def exchange(old_token, from_type, to_type, options) do
    Tuist.Guardian.exchange(old_token, from_type, to_type, options)
  end

  def encode_and_sign(resource, claims \\ %{}, opts \\ []) do
    Tuist.Guardian.encode_and_sign(resource, claims, opts)
  end

  def revoke(token, opts \\ []) do
    Tuist.Guardian.revoke(token, opts)
  end

  def decode_and_verify(token, claims_to_check \\ %{}, opts \\ []) do
    Tuist.Guardian.decode_and_verify(token, claims_to_check, opts)
  end
end
