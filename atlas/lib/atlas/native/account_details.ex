defmodule Atlas.Native.AccountDetails do
  @moduledoc false

  alias Atlas.Accounts
  alias Atlas.Users

  def get(account, user) do
    account = Accounts.get_account(account.id)
    {value, currency} = Accounts.contract_value(account)

    document_fields =
      if Users.has_scope?(user, "documents:read"),
        do: ~w(title document_date summary status)a,
        else: ~w(title document_date status)a

    %{
      fields:
        account
        |> fields(
          ~w(overview_summary overview_summary_generated_at contract_id poc_end_date churned_date churn_reason stripe_customer_id latest_activity_at)a
        )
        |> Map.put(:contract_value, string(value))
        |> Map.put(:contract_currency, string(currency))
        |> Map.put(:parent_account_name, if(account.parent_account, do: account.parent_account.name, else: ""))
        |> Map.put(:handles, Enum.map_join(account.account_handles, ", ", & &1.handle)),
      address: fields(account.address, ~w(street city zip country)a),
      billing: fields(account.billing, ~w(tax_id vat_id sold_to bill_to email phone)a),
      signatory: fields(account.signatory, ~w(name title)a),
      children: records(account.child_accounts, ~w(name primary_domain)a),
      contacts: records(account.contacts, ~w(full_name email title notes linkedin_url is_primary is_decision_maker)a),
      terms:
        records(
          account.terms,
          ~w(payment start_date end_date price_per_seat seats discount total currency on_premise renewal_notice_weeks po_number)a
        ),
      invoices: records(account.invoices, ~w(number due_date amount_value amount_currency status)a),
      documents: records(account.documents, document_fields),
      events:
        Enum.map(account.events, fn event ->
          %{
            id: event.id,
            fields: Map.put(fields(event, ~w(title body kind occurred_at)a), :author_name, name(event.author))
          }
        end),
      outcomes:
        Enum.map(account.outcomes, fn outcome ->
          %{
            id: outcome.id,
            fields:
              outcome
              |> fields(~w(title description status health motion success_measure baseline target target_date)a)
              |> Map.put(:owner_name, name(outcome.owner))
          }
        end),
      service_levels:
        records(
          account.service_levels,
          ~w(name category target measurement_window applies_from applies_until service_credit exclusions)a
        )
    }
  end

  defp records(items, keys), do: Enum.map(items, &%{id: &1.id, fields: fields(&1, keys)})
  defp fields(item, keys), do: Map.new(keys, &{&1, string(if(item, do: Map.get(item, &1)))})
  defp name(nil), do: ""
  defp name(user), do: string(user.name)
  defp string(nil), do: ""
  defp string(%Date{} = value), do: Date.to_iso8601(value)
  defp string(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp string(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp string(value), do: to_string(value)
end
