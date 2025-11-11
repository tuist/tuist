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

  @primary_key false
  schema "cas_outputs" do
    field :node_id, Ch, type: "String"
    field :checksum, Ch, type: "String"
    field :size, Ch, type: "UInt64"
    field :duration, Ch, type: "UInt64"
    field :compressed_size, Ch, type: "UInt64"
    field :operation, Ch, type: "Enum8('download' = 0, 'upload' = 1)"
    field :type, Ch, type: "Nullable(Enum16('swift' = 0, 'sil' = 1, 'sib' = 2, 'image' = 3, 'dSYM' = 4, 'dependencies' = 5, 'emit-module-dependencies' = 6, 'autolink' = 7, 'swiftmodule' = 8, 'swiftdoc' = 9, 'swiftinterface' = 10, 'object' = 11, 'ast-dump' = 12, 'raw-sil' = 13, 'raw-sib' = 14, 'raw-llvm-ir' = 15, 'llvm-ir' = 16, 'llvm-bc' = 17, 'private-swiftinterface' = 18, 'package-swiftinterface' = 19, 'objc-header' = 20, 'swift-dependencies' = 21, 'dependency-scanner-cache' = 22, 'json-dependencies' = 23, 'json-target-info' = 24, 'json-supported-features' = 25, 'json-module-artifacts' = 26, 'imported-modules' = 27, 'module-trace' = 28, 'index-data' = 29, 'index-unit-output-path' = 30, 'yaml-opt-record' = 31, 'bitstream-opt-record' = 32, 'diagnostics' = 33, 'emit-module-diagnostics' = 34, 'dependency-scan-diagnostics' = 35, 'api-baseline-json' = 36, 'abi-baseline-json' = 37, 'const-values' = 38, 'api-descriptor-json' = 39, 'swift-module-summary' = 40, 'module-semantic-info' = 41, 'cached-diagnostics' = 42, 'json-supported-swift-features' = 43, 'modulemap' = 44, 'pch' = 45, 'pcm' = 46, 'tbd' = 47, 'remap' = 48, 'localization-strings' = 49, 'clang-header' = 50))"
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
        type: attrs[:type] && to_string(attrs[:type]),
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
      :operation
    ])
  end
end
