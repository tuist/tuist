defmodule TuistEx.Analytics.ContractTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Contract

  test "version is a stable, semver-shaped string" do
    version = Contract.version()
    assert is_binary(version)
    assert Regex.match?(~r/^\d+\.\d+(\.\d+)?$/, version)
  end
end
