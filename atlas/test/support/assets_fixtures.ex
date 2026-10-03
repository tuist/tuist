defmodule Atlas.AssetsFixtures do
  @moduledoc false

  alias Atlas.Assets.Asset
  alias Atlas.Assets.DataCenter
  alias Atlas.Repo
  alias Atlas.Users.User

  @doc """
  Insert a fixture user for use as an asset holder. Kept here so asset tests
  do not depend on Atlas.MCPToolCase.
  """
  def insert_user_for_asset!(attrs \\ %{}) do
    defaults = %{
      email: "user-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Test User"
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  @doc """
  Build a valid asset attrs map. Callers can override any key.
  """
  def asset_attrs(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      name: "Asset #{n}",
      asset_tag: "TAG-#{n}",
      serial_number: "SN-#{n}",
      manufacturer: "Test Manufacturer",
      model: "Test Model",
      category: "laptop",
      purchased_on: ~D[2026-01-15],
      acquisition_cost: Decimal.new("3600.00"),
      acquisition_currency: "EUR",
      useful_life_months: 36,
      salvage_value: Decimal.new("0"),
      valuation_treatment: "depreciable",
      location: "office"
    }

    Map.merge(defaults, Map.new(attrs))
  end

  @doc """
  Insert an asset via the create changeset. Bypasses lifecycle transitions.
  """
  def insert_asset!(attrs \\ %{}) do
    %Asset{}
    |> Asset.create_changeset(asset_attrs(attrs))
    |> Repo.insert!()
  end

  def data_center_attrs(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      name: "DC #{n}",
      provider: "Test Provider",
      city: "Berlin",
      country: "DE"
    }

    Map.merge(defaults, Map.new(attrs))
  end

  def insert_data_center!(attrs \\ %{}) do
    %DataCenter{}
    |> DataCenter.create_changeset(data_center_attrs(attrs))
    |> Repo.insert!()
  end
end
