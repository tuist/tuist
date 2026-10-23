#!/usr/bin/env bash
# Generates an iOS app with MODULES framework modules shaped like a large
# modular app: every module imports several SDK clang modules and depends on up
# to three earlier modules, so the dependency scan has real work per module.
set -euo pipefail

out="$1"
modules="${MODULES:-120}"
files="${FILES_PER_MODULE:-8}"
salt="${SALT:-$(date +%s)}"

rm -rf "${out}"
mkdir -p "${out}"
cd "${out}"

cat > Tuist.swift <<'EOF'
import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/tuist",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
EOF

imports=(UIKit SwiftUI Combine Foundation MapKit AVFoundation CoreData WebKit CoreLocation Photos)

deps_of() {
  local i=$1 d
  for d in $((i - 1)) $((i / 2)) $((i / 3)); do
    if [ "${d}" -ge 1 ]; then echo "${d}"; fi
  done | sort -un
}

{
  echo 'import ProjectDescription'
  echo
  echo 'func module(_ i: Int, deps: [Int]) -> Target {'
  echo '    .target('
  echo '        name: "Mod\(i)",'
  echo '        destinations: .iOS,'
  echo '        product: .framework,'
  echo '        bundleId: "dev.tuist.bench.Mod\(i)",'
  echo '        deploymentTargets: .iOS("17.0"),'
  echo '        sources: ["Modules/Mod\(i)/**"],'
  echo '        dependencies: deps.map { .target(name: "Mod\($0)") }'
  echo '    )'
  echo '}'
  echo
  echo 'let project = Project('
  echo '    name: "Bench",'
  echo '    targets: ['
  for i in $(seq 1 "${modules}"); do
    deps=$(deps_of "${i}" | paste -sd, -)
    echo "        module(${i}, deps: [${deps}]),"
  done
  echo '        .target('
  echo '            name: "App",'
  echo '            destinations: .iOS,'
  echo '            product: .app,'
  echo '            bundleId: "dev.tuist.bench.App",'
  echo '            deploymentTargets: .iOS("17.0"),'
  echo '            infoPlist: .default,'
  echo '            sources: ["App/**"],'
  printf '            dependencies: ['
  for i in $(seq $((modules - 9)) "${modules}"); do printf '.target(name: "Mod%d"), ' "${i}"; done
  echo ']'
  echo '        ),'
  echo '    ]'
  echo ')'
} > Project.swift

for i in $(seq 1 "${modules}"); do
  dir="Modules/Mod${i}"
  mkdir -p "${dir}"
  deps=$(deps_of "${i}")
  for f in $(seq 1 "${files}"); do
    {
      echo "import ${imports[$(((i + f) % ${#imports[@]}))]}"
      echo "import ${imports[$(((i * 3 + f) % ${#imports[@]}))]}"
      echo "import Foundation"
      for d in ${deps}; do echo "import Mod${d}"; done
      echo
      echo "public struct Mod${i}Type${f}: Hashable, Sendable {"
      echo "    public var id: Int"
      echo "    public var name: String"
      echo "    public init(id: Int, name: String) { self.id = id; self.name = name }"
      echo "    public func describe() -> String { \"\\(name)-\\(id)-${salt}\" }"
      echo "}"
      echo
      echo "public final class Mod${i}Service${f} {"
      echo "    private var items: [Mod${i}Type${f}] = []"
      echo "    public init() {}"
      echo "    public func add(_ item: Mod${i}Type${f}) { items.append(item) }"
      echo "    public func names() -> [String] { items.map { \$0.describe() }.sorted() }"
      for d in ${deps}; do
        echo "    public func use${d}() -> String { Mod${d}Type1(id: ${f}, name: \"m${i}\").describe() }"
      done
      echo "}"
    } > "${dir}/File${f}.swift"
  done
done

mkdir -p App
{
  echo "import SwiftUI"
  for i in $(seq $((modules - 9)) "${modules}"); do echo "import Mod${i}"; done
  echo
  echo "@main"
  echo "struct BenchApp: App {"
  echo "    var body: some Scene { WindowGroup { Text(Mod${modules}Service1().names().joined()) } }"
  echo "}"
} > App/App.swift
