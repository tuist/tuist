defmodule Atlas.InsuranceFixtures do
  @moduledoc false

  alias Atlas.Insurance.Policy
  alias Atlas.Repo

  def policy_attrs(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      provider: "Alte Leipziger",
      product: "Elektronikversicherung ##{n}",
      currency: "EUR",
      sum_insured: Decimal.new("100000.00"),
      provisional_cover_pct: 50,
      annual_premium: Decimal.new("416.50"),
      deductible_per_claim: Decimal.new("250.00"),
      cleanup_pct: 10,
      cleanup_min: Decimal.new("10000.00"),
      cleanup_max: Decimal.new("100000.00"),
      movement_pct: 10,
      mobile_use_pct: 50,
      covers_data: true,
      covers_software: true,
      covers_dongles: true,
      covers_leased: true,
      quote_valid_until: ~D[2026-09-21],
      status: "quoted"
    }

    Map.merge(defaults, Map.new(attrs))
  end

  def insert_policy!(attrs \\ %{}) do
    %Policy{}
    |> Policy.create_changeset(policy_attrs(attrs))
    |> Repo.insert!()
  end
end
