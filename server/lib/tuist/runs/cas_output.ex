defmodule Tuist.Runs.CASOutput do
  @moduledoc """
  A CAS output represents cache upload/download operations for a build run.
  """
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [:build_run_id, :node_id, :operation, :size, :compressed_size, :type],
    sortable: [:node_id, :size, :compressed_size]
  }

  def valid_types do
    [
      "swift",
      "sil",
      "sib",
      "image",
      "dSYM",
      "dependencies",
      "emit-module-dependencies",
      "autolink",
      "swiftmodule",
      "swiftdoc",
      "swiftinterface",
      "object",
      "ast-dump",
      "raw-sil",
      "raw-sib",
      "raw-llvm-ir",
      "llvm-ir",
      "llvm-bc",
      "private-swiftinterface",
      "package-swiftinterface",
      "objc-header",
      "swift-dependencies",
      "dependency-scanner-cache",
      "json-dependencies",
      "json-target-info",
      "json-supported-features",
      "json-module-artifacts",
      "imported-modules",
      "module-trace",
      "index-data",
      "index-unit-output-path",
      "yaml-opt-record",
      "bitstream-opt-record",
      "diagnostics",
      "emit-module-diagnostics",
      "dependency-scan-diagnostics",
      "api-baseline-json",
      "abi-baseline-json",
      "const-values",
      "api-descriptor-json",
      "swift-module-summary",
      "module-semantic-info",
      "cached-diagnostics",
      "json-supported-swift-features",
      "modulemap",
      "pch",
      "pcm",
      "tbd",
      "remap",
      "localization-strings",
      "clang-header",
      "swiftsourceinfo",
      "assembly",
      "unknown"
    ]
  end

  @primary_key false
  schema "cas_outputs" do
    field :node_id, Ch, type: "String"
    field :checksum, Ch, type: "String"
    field :size, Ch, type: "UInt64"
    field :duration, Ch, type: "UInt64"
    field :compressed_size, Ch, type: "UInt64"
    field :operation, Ch, type: "Enum8('download' = 0, 'upload' = 1)"

    field :type, Ch, type: "LowCardinality(String)"

    field :build_run_id, Ch, type: "UUID"
    field :inserted_at, Ch, type: "DateTime"
  end

  def changeset(build_run_id, attrs) do
    %__MODULE__{}
    |> Ecto.Changeset.cast(
      %{
        build_run_id: build_run_id,
        node_id: attrs[:node_id],
        checksum: attrs[:checksum],
        size: attrs[:size],
        duration: attrs[:duration] && trunc(attrs[:duration]),
        compressed_size: attrs[:compressed_size],
        operation: attrs[:operation] && to_string(attrs[:operation]),
        type: (attrs[:type] && to_string(attrs[:type])) || "unknown",
        inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
      },
      [:build_run_id, :node_id, :checksum, :size, :duration, :compressed_size, :operation, :type, :inserted_at]
    )
    |> Ecto.Changeset.validate_required([
      :build_run_id,
      :node_id,
      :checksum,
      :size,
      :duration,
      :compressed_size,
      :operation,
      :type
    ])
    |> Ecto.Changeset.validate_inclusion(:type, valid_types())
  end
end
