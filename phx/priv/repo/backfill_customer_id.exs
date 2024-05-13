alias TuistCloud.Environment
alias TuistCloud.Accounts
alias TuistCloud.Repo
alias TuistCloud.Billing
alias TuistCloud.Accounts.Account

if Billing.enabled?() do
  Repo.all(Account)
  |> Enum.filter(fn account -> account.customer_id == nil end)
  |> Enum.each(fn account ->
    user =
      if account.owner_type == "Organization" do
        organization = Accounts.get_organization_by_id(account.owner_id)
        Accounts.get_organization_members(organization, :admin)
        |> hd

      else
        Accounts.get_user!(account.owner_id)
      end

    customer_id = Billing.create_customer(%{name: account.name, email: user.email})

    account
    |> Ecto.Changeset.change(customer_id: customer_id)
    |> Repo.update!()
  end)
end
