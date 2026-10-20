defmodule Atlas.Accounts.FeatureInterests do
  @moduledoc """
  Records product capabilities that accounts explicitly ask for in account
  timeline events, retaining the event as supporting evidence.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.FeatureInterest
  alias Atlas.Accounts.FeatureInterestAccount
  alias Atlas.Audit
  alias Atlas.Repo

  def list do
    FeatureInterest
    |> order_by([interest], desc: interest.interest_count, desc: interest.last_interested_at, asc: interest.title)
    |> Repo.all()
  end

  def get(id) when is_binary(id) do
    accounts_query = account_interest_query()

    FeatureInterest
    |> preload(accounts: ^accounts_query)
    |> Repo.get(id)
  end

  def get(_id), do: nil

  def change_definition(attrs \\ %{}) when is_map(attrs) do
    %FeatureInterest{}
    |> FeatureInterest.changeset(definition_attrs(attrs))
  end

  def create_definition(attrs, actor \\ nil) when is_map(attrs) do
    changeset = change_definition(attrs)

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, interest} -> audit_definition_creation(interest, actor)
      _result -> :ok
    end)
  end

  def list_for_account(%Account{id: account_id}), do: list_for_account(account_id)

  def list_for_account(account_id) when is_binary(account_id) do
    FeatureInterest
    |> join(:inner, [interest], interest_account in FeatureInterestAccount,
      on: interest_account.feature_interest_id == interest.id
    )
    |> where([_interest, interest_account], interest_account.account_id == ^account_id)
    |> order_by([interest, interest_account], desc: interest_account.last_interested_at, asc: interest.title)
    |> preload(
      [_interest, interest_account],
      accounts:
        ^from(account_interest in FeatureInterestAccount,
          where: account_interest.account_id == ^account_id,
          preload: [:account, :account_event, :feature_interest, :support_thread]
        )
    )
    |> Repo.all()
  end

  def list_for_account(_account_id), do: []

  def get_account_interest(id) when is_binary(id) do
    FeatureInterestAccount
    |> preload([:account, :account_event, :feature_interest])
    |> Repo.get(id)
  end

  def get_account_interest(_id), do: nil

  def get_account_event(%Account{id: account_id}, event_id), do: get_account_event(account_id, event_id)

  def get_account_event(account_id, event_id) when is_binary(account_id) and is_binary(event_id) do
    case Repo.get_by(Event, id: event_id, account_id: account_id) do
      %Event{} = event -> {:ok, event}
      nil -> {:error, :event_not_found}
    end
  end

  def get_account_event(_account_id, _event_id), do: {:error, :event_not_found}

  def record_from_event(event, attrs, actor \\ nil)

  def record_from_event(%Event{account_id: account_id} = event, attrs, actor)
      when is_binary(account_id) and is_map(attrs) do
    with %Account{} = account <- Repo.get(Account, account_id),
         {:ok, normalized} <- normalize(attrs) do
      Repo.transaction(fn ->
        interest = get_or_create_interest!(normalized)
        interest_account = upsert_account_interest!(interest, account, event, normalized)
        interest = refresh_interest_counts!(interest)
        audit_recording(interest, interest_account, account, event, actor)
        %{interest: interest, account_interest: interest_account}
      end)
    else
      nil -> {:error, :account_required}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def record_from_event(_event, _attrs, _actor), do: {:error, :account_required}

  def change_account_interest(attrs \\ %{}) do
    %FeatureInterestAccount{}
    |> FeatureInterestAccount.form_changeset(Map.put_new(attrs, :last_interested_at, utc_now()))
  end

  def change_account_interest_notes(%FeatureInterestAccount{} = interest_account, attrs \\ %{}) do
    FeatureInterestAccount.notes_changeset(interest_account, attrs)
  end

  def update_notes(interest_account, attrs, actor \\ nil)

  def update_notes(%FeatureInterestAccount{id: id}, attrs, actor) when is_map(attrs) do
    with %FeatureInterestAccount{} = interest_account <- Repo.get(FeatureInterestAccount, id),
         %FeatureInterest{} = interest <- Repo.get(FeatureInterest, interest_account.feature_interest_id),
         %Account{} = account <- Repo.get(Account, interest_account.account_id) do
      Repo.transaction(fn ->
        updated_interest_account =
          interest_account
          |> FeatureInterestAccount.notes_changeset(attrs)
          |> Repo.update!()

        audit_notes_update(interest, updated_interest_account, account, actor)
        updated_interest_account
      end)
    else
      nil -> {:error, :not_found}
    end
  end

  def update_notes(_interest_account, _attrs, _actor), do: {:error, :not_found}

  defp normalize(attrs) do
    title = attrs |> value(:title) |> normalize_text()
    summary = attrs |> value(:summary) |> normalize_text()
    notes = attrs |> value(:notes) |> normalize_optional_text()

    changeset =
      %FeatureInterestAccount{}
      |> FeatureInterestAccount.form_changeset(%{
        feature_interest_id: Ecto.UUID.generate(),
        account_id: Ecto.UUID.generate(),
        title: title,
        summary: summary,
        notes: notes,
        last_interested_at: utc_now()
      })

    if changeset.valid? do
      {:ok, %{title: title, canonical_title: canonical_title(title), summary: summary, notes: notes}}
    else
      {:error, changeset}
    end
  end

  defp get_or_create_interest!(normalized) do
    case Repo.get_by(FeatureInterest, canonical_title: normalized.canonical_title) do
      %FeatureInterest{} = interest ->
        interest

      nil ->
        %FeatureInterest{}
        |> FeatureInterest.changeset(%{
          title: normalized.title,
          canonical_title: normalized.canonical_title,
          last_interested_at: utc_now()
        })
        |> Repo.insert!()
    end
  end

  defp upsert_account_interest!(interest, account, event, normalized) do
    attrs = %{
      feature_interest_id: interest.id,
      account_id: account.id,
      account_event_id: event.id,
      summary: normalized.summary,
      notes: normalized.notes,
      last_interested_at: utc_now(),
      metadata: %{"source" => "account_timeline", "event_source" => event.source}
    }

    case Repo.get_by(FeatureInterestAccount, feature_interest_id: interest.id, account_id: account.id) do
      nil ->
        %FeatureInterestAccount{}
        |> FeatureInterestAccount.changeset(attrs)
        |> Repo.insert!()

      %FeatureInterestAccount{} = interest_account ->
        interest_account
        |> FeatureInterestAccount.changeset(attrs)
        |> Repo.update!()
    end
  end

  defp refresh_interest_counts!(interest) do
    interest_count =
      FeatureInterestAccount
      |> where([interest_account], interest_account.feature_interest_id == ^interest.id)
      |> Repo.aggregate(:count)

    last_interested_at =
      FeatureInterestAccount
      |> where([interest_account], interest_account.feature_interest_id == ^interest.id)
      |> select([interest_account], max(interest_account.last_interested_at))
      |> Repo.one()

    interest
    |> FeatureInterest.changeset(%{
      interest_count: interest_count,
      last_interested_at: last_interested_at
    })
    |> Repo.update!()
  end

  defp audit_recording(interest, interest_account, account, event, actor) do
    Audit.record(
      "feature_interest.recorded",
      %{
        target_type: "feature_interest",
        target_id: interest.id,
        target_label: interest.title,
        metadata:
          interest_metadata(account, event, interest_account)
          |> Map.put("source", "account_timeline")
      },
      actor: actor
    )
  end

  defp audit_definition_creation(interest, actor) do
    Audit.record(
      "feature_interest.created",
      %{
        target_type: "feature_interest",
        target_id: interest.id,
        target_label: interest.title,
        metadata: %{"path" => "/commercial/sales/feature-interests/#{interest.id}"}
      },
      actor: actor
    )
  end

  defp audit_notes_update(interest, interest_account, account, actor) do
    event = Repo.get(Event, interest_account.account_event_id)

    Audit.record(
      "feature_interest.notes_updated",
      %{
        target_type: "feature_interest",
        target_id: interest.id,
        target_label: interest.title,
        metadata: interest_metadata(account, event, interest_account)
      },
      actor: actor
    )
  end

  defp interest_metadata(account, event, interest_account) do
    %{
      "account_id" => account.id,
      "account_path" => "/commercial/sales/accounts/#{account.id}",
      "account_event_id" => event && event.id,
      "account_event_path" => event && "/commercial/sales/accounts/#{account.id}#timeline-event-#{event.id}",
      "feature_interest_account_id" => interest_account.id
    }
  end

  defp account_interest_query do
    from(interest_account in FeatureInterestAccount,
      order_by: [desc: interest_account.last_interested_at],
      preload: [:account, :account_event, :feature_interest, :support_thread]
    )
  end

  defp value(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  defp normalize_text(value) when is_binary(value), do: String.trim(value)
  defp normalize_text(_value), do: nil

  defp normalize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_optional_text(_value), do: nil

  defp definition_attrs(attrs) do
    title = attrs |> value(:title) |> normalize_text()
    status = attrs |> value(:status) |> normalize_status()

    %{title: title, canonical_title: canonical_title(title), status: status}
  end

  defp normalize_status(status) do
    if status in FeatureInterest.statuses(), do: status, else: "open"
  end

  defp canonical_title(nil), do: nil
  defp canonical_title(title), do: title |> String.downcase() |> String.replace(~r/\s+/, " ")
  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
