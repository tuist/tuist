defmodule Atlas.Licenses do
  @moduledoc """
  Customer license issuance, validation, extension, and air-gapped checkout operations.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Audit
  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.Licenses.RateLimiter
  alias Atlas.Repo

  @default_page_size 25
  @max_page_size 100
  @sortable_fields ~w(customer expires_on status)

  def sortable_fields, do: @sortable_fields

  def list_licenses(opts \\ []) do
    opts = Keyword.put_new(opts, :page_size, @max_page_size)
    {licenses, _meta} = list_licenses_page(opts)
    licenses
  end

  def list_licenses_page(opts \\ []) do
    filters = Keyword.get(opts, :filters, [])
    query = Keyword.get(opts, :query)
    sort_by = Keyword.get(opts, :sort_by)
    sort_order = Keyword.get(opts, :sort_order, "desc")
    page = opts |> Keyword.get(:page, 1) |> normalize_page()
    page_size = opts |> Keyword.get(:page_size, @default_page_size) |> normalize_page_size()

    License
    |> join(:inner, [license], account in assoc(license, :account), as: :account)
    |> maybe_apply_filters(filters)
    |> maybe_filter_query(query)
    |> apply_sort(sort_by, sort_order)
    |> preload([account: account], account: account)
    |> Flop.run(%Flop{page: page, page_size: page_size}, for: License)
  end

  def get_license(id) when is_binary(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> License |> preload(:account) |> Repo.get(id)
      :error -> nil
    end
  end

  def get_license(_id), do: nil

  def list_licenses_expiring_on(%Date{} = date) do
    License
    |> where([license], license.expires_on == ^date)
    |> preload(:account)
    |> Repo.all()
  end

  def change_license_request(attrs \\ %{}) do
    License.request_changeset(%License{}, attrs)
  end

  def create_license(attrs) when is_map(attrs) do
    request_changeset = change_license_request(attrs)

    with {:ok, request} <- Ecto.Changeset.apply_action(request_changeset, :insert),
         {:ok, account} <- fetch_license_account(request.account_id, request_changeset),
         issued = Issuer.issue(request.expires_on),
         {:ok, license} <- persist_license(account, issued) do
      audit_license("license.created", license, account, %{
        "expires_on" => Date.to_iso8601(license.expires_on)
      })

      {:ok, %{license | account: account}}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  def change_license_extension(%License{} = license, attrs \\ %{}) do
    License.extension_changeset(license, attrs)
  end

  def extend_license(%License{} = license, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      current_license =
        License
        |> where([current_license], current_license.id == ^license.id)
        |> lock("FOR UPDATE")
        |> preload(:account)
        |> Repo.one()

      case current_license do
        nil ->
          Repo.rollback(:not_found)

        current_license ->
          previous_expiration_date = current_license.expires_on

          current_license
          |> change_license_extension(attrs)
          |> Repo.update()
          |> case do
            {:ok, extended_license} -> {extended_license, previous_expiration_date}
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
    |> case do
      {:ok, {license, previous_expiration_date}} ->
        audit_license("license.extended", license, license.account, %{
          "previous_expires_on" => Date.to_iso8601(previous_expiration_date),
          "expires_on" => Date.to_iso8601(license.expires_on)
        })

        {:ok, license}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}

      {:error, :not_found} ->
        {:error,
         license
         |> change_license_extension(attrs)
         |> Ecto.Changeset.add_error(:base, "license no longer exists")}
    end
  end

  def validate_online_key(key) when is_binary(key) do
    license =
      License
      |> preload(:account)
      |> Repo.get_by(key_hash: Issuer.key_hash(key))

    with :ok <- rate_limit_validation(license) do
      if license do
        audit_license("license.validated", license, license.account, %{
          "expires_on" => Date.to_iso8601(license.expires_on),
          "valid" => not Date.before?(license.expires_on, Date.utc_today())
        })
      end

      {:ok, Issuer.validation_payload(license)}
    end
  end

  def check_out_air_gapped(%License{} = license) do
    license = Repo.preload(license, :account)

    case Issuer.certificate(license) do
      {:ok, certificate} ->
        audit_license("license.air_gapped_checked_out", license, license.account, %{
          "expires_on" => Date.to_iso8601(license.expires_on)
        })

        {:ok,
         %{
           contents: Base.encode64(certificate),
           filename: air_gapped_filename(license.account.name)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def air_gapped_filename(customer_name) do
    slug =
      customer_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    "#{slug}-tuist-license.key"
  end

  def error_message(:signing_key_not_configured), do: "Atlas license signing is not configured."
  def error_message(:invalid_signing_key), do: "Atlas license signing is misconfigured."
  def error_message(_reason), do: "The license operation could not be completed."

  defp maybe_apply_filters(query, filters) do
    Enum.reduce(filters, query, &apply_filter/2)
  end

  defp apply_filter(%{field: :account_id, operator: :==, value: account_id}, query) when is_binary(account_id) do
    where(query, [license], license.account_id == ^account_id)
  end

  defp apply_filter(%{field: :account_id, operator: :!=, value: account_id}, query) when is_binary(account_id) do
    where(query, [license], license.account_id != ^account_id)
  end

  defp apply_filter(%{field: :status, operator: operator, value: status}, query)
       when operator in [:==, :!=] and status in ["active", "expired"] do
    active? = status == "active"
    matching? = if operator == :==, do: active?, else: not active?
    today = Date.utc_today()

    if matching? do
      where(query, [license], license.expires_on >= ^today)
    else
      where(query, [license], license.expires_on < ^today)
    end
  end

  defp apply_filter(_filter, query), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        query

      value ->
        pattern = "%#{value}%"

        where(
          query,
          [account: account],
          ilike(account.name, ^pattern) or ilike(account.primary_domain, ^pattern)
        )
    end
  end

  defp maybe_filter_query(query, _value), do: query

  defp apply_sort(query, "customer", sort_order) do
    direction = sort_direction(sort_order)
    order_by(query, [license, account: account], [{^direction, account.name}, desc: license.id])
  end

  defp apply_sort(query, "expires_on", sort_order) do
    direction = sort_direction(sort_order)
    order_by(query, [license], [{^direction, license.expires_on}, desc: license.inserted_at, desc: license.id])
  end

  defp apply_sort(query, "status", sort_order) do
    direction = sort_direction(sort_order)
    today = Date.utc_today()

    order_by(query, [license], [
      {^direction, fragment("CASE WHEN ? < ? THEN 1 ELSE 0 END", license.expires_on, ^today)},
      {^direction, license.expires_on},
      {:desc, license.id}
    ])
  end

  defp apply_sort(query, _sort_by, _sort_order) do
    order_by(query, [license], asc: license.expires_on, desc: license.inserted_at, desc: license.id)
  end

  defp sort_direction("asc"), do: :asc
  defp sort_direction(_sort_order), do: :desc

  defp fetch_license_account(account_id, changeset) do
    case Atlas.UUIDv7.cast(account_id) do
      {:ok, account_id} ->
        case Repo.get(Account, account_id) do
          %Account{} = account ->
            if Account.license_eligible?(account) do
              {:ok, account}
            else
              {:error, Ecto.Changeset.add_error(changeset, :account_id, "must belong to a customer or POC account")}
            end

          nil ->
            {:error, Ecto.Changeset.add_error(changeset, :account_id, "does not exist")}
        end

      :error ->
        {:error, Ecto.Changeset.add_error(changeset, :account_id, "does not exist")}
    end
  end

  defp normalize_page(page) when is_integer(page) and page > 0, do: page
  defp normalize_page(_page), do: 1

  defp normalize_page_size(page_size) when is_integer(page_size) and page_size > 0 do
    min(page_size, @max_page_size)
  end

  defp normalize_page_size(_page_size), do: @default_page_size

  defp rate_limit_validation(nil), do: :ok
  defp rate_limit_validation(%License{key_hash: key_hash}), do: RateLimiter.check(key_hash)

  defp persist_license(account, issued) do
    %License{account_id: account.id}
    |> License.issued_changeset(%{
      key: issued.key,
      key_hash: issued.key_hash,
      signing_key: issued.signing_key,
      expires_on: issued.expires_on
    })
    |> Repo.insert()
  end

  defp audit_license(action, license, account, metadata) do
    Audit.record(action, %{
      target_type: "license",
      target_id: license.id,
      target_label: account.name,
      metadata:
        Map.merge(metadata, %{
          "account_id" => account.id,
          "account_path" => "/commercial/sales/accounts/#{account.id}",
          "path" => "/commercial/sales/licenses"
        })
    })
  end
end
