defmodule Tuist.Kura.Identity do
  @moduledoc """
  Permanent Kura namespace and its account owner. The initial handle remains
  the storage, TLS and workload identity across account renames. Only the
  authorization handle follows the account's current name.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.SelfHostedClient
  alias Tuist.Kura.Server
  alias Tuist.Repo

  def tenant_id(%{kura_tenant_id: tenant}) when is_binary(tenant), do: tenant
  def tenant_id(%{name: name}), do: String.downcase(name)

  def account(tenant) when is_binary(tenant) do
    Repo.one(from(a in Account, where: a.kura_tenant_id == ^tenant))
  end

  def rename_allowed?(account) do
    Environment.env() not in [:can, :prod] or
      FunWithFlags.enabled?(:kura_account_rename, for: account) or
      not (Repo.exists?(from(s in Server, where: s.account_id == ^account.id)) or
             Repo.exists?(from(c in SelfHostedClient, where: c.account_id == ^account.id)))
  end

  def account_ids(tenants) do
    tenants = tenants |> Enum.filter(&is_binary/1) |> Enum.uniq()

    ids =
      from(r in "account_handle_reservations", where: r.name in ^tenants, select: {r.name, r.account_id})
      |> Repo.all()
      |> Map.new(fn {name, id} -> {String.downcase(name), id} end)

    for tenant <- tenants, {:ok, id} <- [Map.fetch(ids, String.downcase(tenant))], into: %{}, do: {tenant, id}
  end
end
