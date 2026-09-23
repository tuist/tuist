defmodule Atlas.Accounts.AccountAttention do
  @moduledoc """
  Read-only accessors for historical account follow-up suggestions.

  The generation, delivery, and disposition pipeline was replaced by
  `Atlas.Nudges` in the same release. This module exists so already-
  recorded suggestions remain queryable through the account page and
  through the `list_account_attention_suggestions` MCP tool. The table
  and this module are removed in a follow-up PR after one deployment
  window.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountAttentionSuggestion
  alias Atlas.Repo

  def list(account_or_id, opts \\ [])

  def list(%Account{id: account_id}, opts), do: list(account_id, opts)

  def list(account_id, opts) when is_binary(account_id) do
    statuses = Keyword.get(opts, :statuses)

    AccountAttentionSuggestion
    |> where([suggestion], suggestion.account_id == ^account_id)
    |> maybe_filter_statuses(statuses)
    |> order_by([suggestion], desc: suggestion.inserted_at)
    |> Repo.all()
  end

  def get(id) when is_binary(id), do: Repo.get(AccountAttentionSuggestion, id)

  def get(%Account{id: account_id}, id) when is_binary(id) do
    AccountAttentionSuggestion
    |> where([suggestion], suggestion.account_id == ^account_id)
    |> Repo.get(id)
  end

  defp maybe_filter_statuses(query, nil), do: query
  defp maybe_filter_statuses(query, []), do: query
  defp maybe_filter_statuses(query, statuses), do: where(query, [suggestion], suggestion.status in ^statuses)
end
