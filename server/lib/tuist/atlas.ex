defmodule Tuist.Atlas do
  @moduledoc """
  Read models exposed to the internal Atlas workload.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.Account

  def customer_context(account_handle) when is_binary(account_handle) and account_handle != "" do
    case Accounts.get_account_by_handle(account_handle) do
      %Account{} ->
        {:ok, %{current_month_remote_cache_hits: 0}}

      nil ->
        {:error, :not_found}
    end
  end

  def customer_context(_account_handle), do: {:error, :not_found}
end
