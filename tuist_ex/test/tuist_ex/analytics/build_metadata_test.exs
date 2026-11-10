defmodule TuistEx.Analytics.BuildMetadataTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.BuildMetadata

  test "explicit values win and automatic observations never displace customer entries" do
    explicit = Map.new(1..20, &{"customer.#{&1}", "value"})
    observations = %{"tuist.cpu.available_processors" => "8"}
    assert BuildMetadata.merge(explicit, observations, 20) == explicit
    assert BuildMetadata.merge(explicit, observations, 64) == Map.merge(explicit, observations)

    assert BuildMetadata.merge(
             %{"tuist.gradle.max_workers" => "explicit"},
             %{"tuist.gradle.max_workers" => "8"},
             64
           ) == %{"tuist.gradle.max_workers" => "explicit"}
  end

  test "discovery is credential-free and fails closed to the legacy allowance" do
    request = fn :get, url, nil, [] ->
      assert url == "https://example.com/path/api/metadata/limits"
      {:ok, 200, %{"max_values" => 64}}
    end

    assert BuildMetadata.discover(
             "https://user:secret@example.com/path?token=secret#fragment",
             request
           ) == 64

    for response <- [
          {:ok, 404, %{}},
          {:ok, 200, %{}},
          {:ok, 200, %{"max_values" => 65}},
          {:ok, 200, %{"max_values" => "64"}},
          {:error, :timeout}
        ] do
      assert BuildMetadata.discover("https://example.com", fn _, _, _, _ -> response end) == 20
    end
  end

  test "discovery is only needed for payloads over the legacy limit" do
    request = fn _, _, _, _ -> flunk("unexpected discovery") end
    payload = %{custom_metadata: %{tags: ["ci"], values: %{"customer.key" => "value"}}}

    enriched =
      BuildMetadata.enrich(payload, "https://example.com",
        build_metadata_observations: %{"tuist.os.type" => "linux"},
        metadata_limit_request: request
      )

    assert enriched.custom_metadata.tags == ["ci"]

    assert enriched.custom_metadata.values == %{
             "customer.key" => "value",
             "tuist.os.type" => "linux"
           }
  end

  test "runner names are opt-in and environment collection is allowlisted" do
    environment = %{
      "RUNNER_NAME" => "private-runner",
      "USER" => "private-user",
      "HOSTNAME" => "private-host",
      "SECRET" => "secret"
    }

    values = BuildMetadata.observations(environment: &Map.get(environment, &1))
    refute "private-runner" in Map.values(values)
    refute "private-user" in Map.values(values)
    refute "private-host" in Map.values(values)
    refute "secret" in Map.values(values)
    opted_in = Map.put(environment, "TUIST_BUILD_METADATA_RUNNER_NAME", "1")

    assert BuildMetadata.observations(environment: &Map.get(opted_in, &1))["tuist.ci.runner_name"] ==
             "private-runner"
  end
end
