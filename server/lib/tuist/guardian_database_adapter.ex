defmodule Tuist.GuardianDatabaseAdapter do
  @moduledoc """
  Stores Guardian tokens while allowing the same signed token to be persisted more than once.
  """

  @behaviour Guardian.DB.Adapter

  alias Guardian.DB.EctoAdapter

  @default_schema_name "guardian_tokens"

  @impl true
  defdelegate one(claims, options), to: EctoAdapter

  @impl true
  def insert(changeset, options) do
    prefix = Keyword.get(options, :prefix)
    repo = Keyword.fetch!(options, :repo)

    data =
      changeset
      |> Map.fetch!(:data)
      |> Ecto.put_meta(source: Keyword.get(options, :schema_name, @default_schema_name))
      |> Ecto.put_meta(prefix: prefix)

    repo.insert(%{changeset | data: data},
      prefix: prefix,
      on_conflict: :nothing,
      conflict_target: [:jti, :aud]
    )
  end

  @impl true
  defdelegate delete(record, options), to: EctoAdapter

  @impl true
  defdelegate delete_by_sub(subject, options), to: EctoAdapter

  @impl true
  defdelegate purge_expired_tokens(timestamp, options), to: EctoAdapter
end
