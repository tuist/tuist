defmodule TuistRegistry.S3Test do
  use ExUnit.Case
  use Mimic

  alias ExAws.Operation.S3, as: S3Operation
  alias TuistRegistry.S3

  setup :set_mimic_from_context

  setup do
    stub(TuistRegistry.Config, :registry_bucket, fn -> "test-registry-bucket" end)
    :ok
  end

  describe "exists?/2" do
    test "does not cache positive results" do
      key = "registry/swift/apple/swift-argument-parser/1.0.0/source_archive.zip"
      cache_key = {:registry, key}
      {:ok, true} = Cachex.del(S3.exists_cache_name(), cache_key)

      {:ok, request_count} = Agent.start_link(fn -> 0 end)

      expect(ExAws.S3, :head_object, 2, fn "test-registry-bucket", ^key ->
        %S3Operation{path: "head"}
      end)

      expect(ExAws, :request, 2, fn %S3Operation{}, _opts ->
        Agent.get_and_update(request_count, fn count ->
          response =
            case count do
              0 -> {:ok, %{status_code: 200}}
              1 -> {:error, {:http_error, 404, ""}}
            end

          {response, count + 1}
        end)
      end)

      assert S3.exists?(key, type: :registry)
      refute S3.exists?(key, type: :registry)
      assert Agent.get(request_count, & &1) == 2
    end
  end

  describe "list_objects/2" do
    test "returns object keys for a prefix" do
      prefix = "registry/metadata/"

      expect(ExAws.S3, :list_objects_v2, fn "test-registry-bucket", opts ->
        assert Keyword.get(opts, :prefix) == prefix
        %S3Operation{path: prefix}
      end)

      expect(ExAws, :stream!, fn %S3Operation{} ->
        [
          %{key: "registry/metadata/apple/swift-argument-parser/index.json"},
          %{key: "registry/metadata/pointfreeco/swift-composable-architecture/index.json"}
        ]
      end)

      assert S3.list_objects(prefix, type: :registry) ==
               {:ok,
                [
                  "registry/metadata/apple/swift-argument-parser/index.json",
                  "registry/metadata/pointfreeco/swift-composable-architecture/index.json"
                ]}
    end
  end
end
