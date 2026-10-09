defmodule Tuist.ReportActor do
  @moduledoc """
  Attribution is independent of publishing authorization. A reported identifier
  is an opaque, organization-scoped claim, never a credential or a user lookup.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Repo

  @fields [:actor_account_id, :claimed_actor_id, :submission_auth]

  def fields, do: @fields

  def preload(nil), do: nil
  def preload([]), do: []
  def preload([%schema{} | _] = records), do: Repo.preload(records, actor_associations(schema))
  def preload(%schema{} = record), do: Repo.preload(record, actor_associations(schema))

  defp actor_associations(schema) do
    Enum.filter([:actor_account, :ran_by_account, :built_by_account], &(&1 in schema.__schema__(:associations)))
  end

  def valid_identifier?(value) when is_binary(value) do
    byte_size(value) in 1..128 and String.valid?(value) and
      Regex.match?(~r/\A[\x21-\x7e]+\z/, value)
  end

  def valid_identifier?(_), do: false

  def attributes(conn), do: Map.fetch!(conn.assigns, :report_actor)

  def verified_account_filter(query, %Flop.Filter{op: :==, value: value}, _opts) do
    from(r in query, where: fragment("if(? = '', ?, ?)", r.submission_auth, r.account_id, r.actor_account_id) == ^value)
  end

  def verified_account_filter(query, %Flop.Filter{op: :!=, value: value}, _opts) do
    from(r in query, where: fragment("if(? = '', ?, ?)", r.submission_auth, r.account_id, r.actor_account_id) != ^value)
  end

  def actor(record, legacy_name \\ nil) do
    claimed =
      case Map.get(record, :claimed_actor_id, "") do
        "" -> Map.get(Map.get(record, :custom_values) || %{}, "tuist.reported_user", "")
        value -> value
      end

    claimed = if valid_identifier?(claimed), do: claimed, else: ""
    submission = Map.get(record, :submission_auth, "")

    case Map.get(record, :actor_account) do
      %Account{name: name} -> presentation(name, :verified, submission, claimed, name)
      _ -> fallback_actor(record, claimed, submission, legacy_name)
    end
  end

  defp fallback_actor(record, claimed, "", legacy_name) do
    case legacy_name || legacy_account_name(record) do
      nil -> claimed_presentation(claimed, "")
      name -> presentation(name, :legacy, "", claimed)
    end
  end

  defp fallback_actor(_record, claimed, submission, _legacy_name) when claimed != "" do
    presentation(claimed, :reported, submission, claimed)
  end

  defp fallback_actor(_record, _claimed, submission, _legacy_name) do
    presentation("Unknown", :unknown, submission, "")
  end

  defp claimed_presentation("", submission), do: presentation("Unknown", :unknown, submission, "")
  defp claimed_presentation(claimed, submission), do: presentation(claimed, :reported, submission, claimed)

  defp presentation(name, source, submission, claimed, verified \\ nil) do
    %{
      name: name,
      source: source,
      submission_auth: submission,
      verified_account_handle: verified,
      claimed_actor_id: claimed
    }
  end

  defp legacy_account_name(record) do
    Enum.find_value([:ran_by_account, :built_by_account], fn association ->
      case Map.get(record, association) do
        %Account{name: name} -> name
        _ -> nil
      end
    end)
  end
end
