defmodule Tuist.IngestRepo.Migrations.AddTypeEnumToCasOutputs do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE cas_outputs
    ADD COLUMN type Enum16(
      'swift' = 0, 'sil' = 1, 'sib' = 2, 'image' = 3, 'dSYM' = 4, 'dependencies' = 5,
      'emit-module-dependencies' = 6, 'autolink' = 7, 'swiftmodule' = 8, 'swiftdoc' = 9,
      'swiftinterface' = 10, 'object' = 11, 'ast-dump' = 12, 'raw-sil' = 13, 'raw-sib' = 14,
      'raw-llvm-ir' = 15, 'llvm-ir' = 16, 'llvm-bc' = 17, 'private-swiftinterface' = 18,
      'package-swiftinterface' = 19, 'objc-header' = 20, 'swift-dependencies' = 21,
      'dependency-scanner-cache' = 22, 'json-dependencies' = 23, 'json-target-info' = 24,
      'json-supported-features' = 25, 'json-module-artifacts' = 26, 'imported-modules' = 27,
      'module-trace' = 28, 'index-data' = 29, 'index-unit-output-path' = 30,
      'yaml-opt-record' = 31, 'bitstream-opt-record' = 32, 'diagnostics' = 33,
      'emit-module-diagnostics' = 34, 'dependency-scan-diagnostics' = 35,
      'api-baseline-json' = 36, 'abi-baseline-json' = 37, 'const-values' = 38,
      'api-descriptor-json' = 39, 'swift-module-summary' = 40, 'module-semantic-info' = 41,
      'cached-diagnostics' = 42, 'json-supported-swift-features' = 43, 'modulemap' = 44,
      'pch' = 45, 'pcm' = 46, 'tbd' = 47, 'remap' = 48, 'localization-strings' = 49, 'clang-header' = 50,
      'unknown' = 255
    ) DEFAULT 'unknown'
    """)
  end

  def down do
    execute("ALTER TABLE cas_outputs DROP COLUMN type")
  end
end
