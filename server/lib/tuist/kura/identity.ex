defmodule Tuist.Kura.Identity do
  @moduledoc """
  Permanent Kura namespace and its account owner. The initial handle remains
  the storage, peer TLS and workload identity across account renames. Client
  endpoints and authorization follow the account's current name.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Regions
  alias Tuist.Kura.SelfHostedClient
  alias Tuist.Kura.Server
  alias Tuist.Repo

  def tenant_id(%{kura_tenant_id: tenant}) when is_binary(tenant), do: tenant
  def tenant_id(%{name: name}), do: String.downcase(name)

  def account(tenant) when is_binary(tenant) do
    Repo.one(from(a in Account, where: a.kura_tenant_id == ^tenant))
  end

  def account_for_handle(handle) when is_binary(handle) do
    Repo.one(
      from(a in Account,
        join: r in "account_handle_reservations",
        on: r.account_id == a.id,
        where: r.name == ^String.downcase(handle),
        select: a
      )
    )
  end

  def handles(account) do
    reserved = Repo.all(from(r in "account_handle_reservations", where: r.account_id == ^account.id, select: r.name))
    [account.name, tenant_id(account) | reserved] |> Enum.map(&String.downcase/1) |> Enum.uniq() |> Enum.sort()
  end

  # Only an endpoint that passed activation's DNS + HTTPS probe is a redirect
  # target. While provisioning the new name, old URLs continue serving in place.
  def endpoint_redirects(account) do
    aliases = handles(account) -- [String.downcase(account.name)]

    for server <- Repo.all(from(s in Server, where: s.account_id == ^account.id and s.status == :active)),
        {:ok, region} <- [Regions.fetch(server.region)],
        not Regions.private?(region),
        canonical = Provisioner.public_url(account, server),
        is_binary(canonical) and server.url == canonical,
        handle <- aliases,
        source = Provisioner.public_url(%{account | name: handle}, server),
        is_binary(source),
        host = URI.parse(source).host,
        is_binary(host),
        into: %{},
        do: {host, canonical}
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
