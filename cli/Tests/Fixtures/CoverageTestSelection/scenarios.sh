#!/usr/bin/env bash
# Builds the coverage test selection test bed's git history. See README.md.
#
#   scenarios.sh build <generated|xcodeproj> <output-dir>
#   scenarios.sh checkout <repo> <scenario>
#   scenarios.sh refs <repo>
#   scenarios.sh check <repo>
set -euo pipefail

fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  sed -n '4,7p' "${BASH_SOURCE[0]}" | sed 's/^# *//' >&2
  exit 64
}

# Fixed identity, dates and configuration keep every commit SHA identical across machines.
commit_index=0
git_commit() {
  local message=$1
  local date=$((1767225600 + commit_index * 60))
  commit_index=$((commit_index + 1))
  GIT_AUTHOR_NAME="Tuist Test Bed" GIT_AUTHOR_EMAIL="testbed@tuist.dev" GIT_AUTHOR_DATE="@$date +0000" \
    GIT_COMMITTER_NAME="Tuist Test Bed" GIT_COMMITTER_EMAIL="testbed@tuist.dev" GIT_COMMITTER_DATE="@$date +0000" \
    git -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m "$message"
}

commit_all() {
  git add -A
  git_commit "$1"
}

branch_from_baseline() {
  git checkout -q -B "$1" baseline
}

edit_discount() {
  cat >Core/Sources/Discount.swift <<'EOF'
public enum Discount {
    public static func apply(percent: Int, to price: Money) -> Money {
        let keptPercent = 100 - percent
        return Money(cents: price.cents * keptPercent / 100)
    }
}
EOF
}

edit_discount_revision() {
  git show baseline:Core/Sources/Discount.swift >Core/Sources/Discount.swift
  printf '\n// Revision %s\n' "$1" >>Core/Sources/Discount.swift
}

edit_money() {
  cat >Core/Sources/Money.swift <<'EOF'
public struct Money: Equatable, PriceDisplaying {
    public let cents: Cents

    public init(cents: Cents) {
        self.cents = cents
    }

    public var formatted: String {
        let whole = cents / 100
        let fraction = cents % 100
        return "$\(whole).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents + rhs.cents)
    }
}
EOF
}

edit_catalog() {
  sed -i.bak 's/products.first { $0.sku == sku }/products.first(where: { $0.sku == sku })/' Catalog/Sources/Catalog.swift
  rm Catalog/Sources/Catalog.swift.bak
  grep -q 'first(where:' Catalog/Sources/Catalog.swift
}

edit_search() {
  cat >Catalog/Sources/Search.swift <<'EOF'
public enum ProductSearch {
    public static func matches(name: String, query: String) -> Bool {
        if query.isEmpty { return true }
        return name.localizedCaseInsensitiveContains(query)
    }
}
EOF
}

write_featured() {
  cat >Catalog/Sources/Featured.swift <<'EOF'
public enum Featured {
    public static func sku() -> String {
        "coffee"
    }
}
EOF
}

# Plain Xcode projects list every file in project.pbxproj, so removing one edits it too.
remove_from_project() {
  grep -vF "/* $1" Shop.xcodeproj/project.pbxproj >Shop.xcodeproj/project.pbxproj.new
  mv Shop.xcodeproj/project.pbxproj.new Shop.xcodeproj/project.pbxproj
}

replace_in() {
  local file=$1 from=$2 to=$3
  FROM=$from TO=$to perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$file"
  grep -qF "$to" "$file"
}

build() {
  local variant=$1 output=$2
  case "$variant" in
    generated | xcodeproj) ;;
    *) usage ;;
  esac
  if [ -e "$output" ] && [ -n "$(ls -A "$output")" ]; then
    echo "$output is not empty" >&2
    exit 1
  fi
  mkdir -p "$output"
  output=$(cd "$output" && pwd)
  local excludes=(--exclude .DS_Store --exclude xcuserdata --exclude Derived --exclude .build
    --exclude 'Shop.xcworkspace')
  if [ "$variant" = generated ]; then excludes+=(--exclude 'Shop.xcodeproj'); fi
  rsync -a "${excludes[@]}" "$fixture/common/" "$output/"
  rsync -a "${excludes[@]}" "$fixture/$variant/" "$output/"

  cd "$output"
  git init -q -b main
  git config core.autocrlf false
  git config core.fileMode true
  git config core.excludesFile /dev/null

  commit_all "Shop: baseline"
  git tag baseline

  branch_from_baseline feature/source-change
  edit_discount
  commit_all "Refactor the discount calculation"
  git tag checkout/source-change

  branch_from_baseline feature/shared-file
  edit_money
  commit_all "Rename locals in Money"
  git tag checkout/shared-file

  branch_from_baseline feature/resource-change
  replace_in Catalog/Resources/products.json '"Filter coffee"' '"Pour-over coffee"'
  commit_all "Describe the coffee"
  git tag checkout/resource-change

  branch_from_baseline feature/asset-catalog-change
  replace_in App/Resources/Assets.xcassets/Brand.colorset/Contents.json '"blue" : "0.353"' '"blue" : "0.400"'
  commit_all "Brighten the brand color"
  git tag checkout/asset-catalog-change

  branch_from_baseline feature/test-file-change
  replace_in CoreTests/DiscountTests.swift 'Money(cents: 1000)), Money(cents: 900))' \
    'Money(cents: 1000)), Money(cents: 900), "10% off $10.00 is $9.00")'
  commit_all "Explain the discount assertion"
  git tag checkout/test-file-change

  branch_from_baseline feature/new-test
  replace_in CoreTests/DiscountTests.swift '    func testZeroPercentKeepsPrice() {' '    func testFiftyPercentOff() {
        XCTAssertEqual(Discount.apply(percent: 50, to: Money(cents: 1000)), Money(cents: 500))
    }

    func testZeroPercentKeepsPrice() {'
  commit_all "Test a 50% discount"
  git tag checkout/new-test

  branch_from_baseline feature/failed-at-baseline
  printf '\nThe failed-at-baseline scenario changes only this file.\n' >>docs/notes.md
  commit_all "Note the failed test"
  git tag checkout/failed-at-baseline

  branch_from_baseline feature/carried-evidence
  edit_money
  commit_all "Rename locals in Money"
  git tag run/carried-evidence/1
  edit_discount
  commit_all "Refactor the discount calculation"
  git tag checkout/carried-evidence

  branch_from_baseline feature/evidence-window
  local revision
  for revision in $(seq 1 22); do
    edit_discount_revision "$revision"
    commit_all "Discount revision $revision"
    if [ "$revision" -le 21 ]; then git tag "run/evidence-window/$(printf '%02d' "$revision")"; fi
  done
  git tag checkout/window-at-cap run/evidence-window/21
  git tag checkout/window-over-cap
  git tag checkout/window-unmeasured

  branch_from_baseline feature/diff-too-large
  edit_discount
  mkdir bulk
  local index
  for index in $(seq -w 1 5001); do printf 'bulk %s\n' "$index" >"bulk/$index.txt"; done
  commit_all "Refactor the discount calculation and add 5,001 unowned files"
  git tag checkout/diff-too-large

  branch_from_baseline feature/tracked-file
  printf 'GCC_TREAT_WARNINGS_AS_ERRORS = NO\n' >>Configs/Base.xcconfig
  commit_all "Spell out the warnings setting"
  git tag checkout/tracked-file

  branch_from_baseline feature/declaration-only-change
  printf '\npublic typealias SKU = String\n' >>Core/Sources/Models.swift
  commit_all "Add the SKU alias"
  git tag checkout/declaration-only-change

  branch_from_baseline feature/unowned-file
  printf '\nThis file belongs to no target.\n' >>README.md
  edit_discount
  commit_all "Refactor the discount calculation and update the README"
  git tag checkout/unowned-file

  branch_from_baseline feature/unowned-file-only
  printf '\nThis file belongs to no target.\n' >>README.md
  commit_all "Update the README"
  git tag checkout/unowned-file-only

  branch_from_baseline feature/unowned-test-fixture
  replace_in CatalogTests/Fixtures/catalog-fixture.json '"price_cents": 275 }' '"price_cents": 275, "description": "Plain bagel" }'
  commit_all "Describe the fixture bagel"
  git tag checkout/unowned-test-fixture

  branch_from_baseline feature/dirty-checkout
  printf '\nThe dirty-checkout scenario starts from this commit.\n' >>docs/notes.md
  commit_all "Start the dirty work"
  git tag checkout/dirty-checkout

  branch_from_baseline feature/swift-testing-only-source
  edit_search
  commit_all "Return early from an empty search"
  git tag checkout/swift-testing-only-source

  branch_from_baseline feature/local-merge
  edit_discount
  commit_all "Refactor the discount calculation"
  git tag head/local-merge

  git checkout -q main
  edit_catalog
  commit_all "Look products up with first(where:)"
  git tag main/catalog-change

  # GitHub checks out a synthetic merge of the pull request into its base: first parent the base, second the head.
  git checkout -q --detach main
  git merge -q --no-ff --no-commit head/local-merge >/dev/null 2>&1
  git_commit "Merge feature/local-merge into main"
  git tag checkout/local-merge

  git checkout -q main
  edit_discount
  commit_all "Refactor the discount calculation on main"
  git tag checkout/default-branch

  branch_from_baseline feature/receipt-change
  replace_in App/Sources/Receipt.swift 'var lines = items.map' 'var lines: [String] = items.map'
  commit_all "Spell out the receipt lines' type"
  git tag checkout/receipt-change

  branch_from_baseline feature/test-helper-change
  replace_in CoreTests/Support/Prices.swift 'cents(1000)' 'cents(10 * 100)'
  commit_all "Write ten dollars in cents"
  git tag checkout/test-helper-change

  branch_from_baseline feature/ui-test-base-class-change
  replace_in AppUITests/ShopUITestCase.swift '        app.terminate()
        super.tearDown()' '        app?.terminate()
        super.tearDown()'
  commit_all "Tolerate a test that never launched the app"
  git tag checkout/ui-test-base-class-change

  branch_from_baseline feature/deleted-test-file
  git rm -q CoreTests/MoneyTests.swift
  if [ "$variant" = xcodeproj ]; then remove_from_project MoneyTests.swift; fi
  commit_all "Remove the Money tests"
  git tag checkout/deleted-test-file

  branch_from_baseline feature/renamed-source
  git mv Core/Sources/Discount.swift Core/Sources/PercentDiscount.swift
  if [ "$variant" = xcodeproj ]; then
    sed -i.bak 's/Discount\.swift/PercentDiscount.swift/g' Shop.xcodeproj/project.pbxproj
    rm Shop.xcodeproj/project.pbxproj.bak
  fi
  commit_all "Rename Discount.swift to PercentDiscount.swift"
  git tag checkout/renamed-source

  git checkout -q main
  refs "$output"
}

scenario_branch() {
  case "$1" in
    default-branch) echo main ;;
    local-merge) echo "" ;;
    window-at-cap | window-over-cap | window-unmeasured) echo feature/evidence-window ;;
    no-baseline | stale-base | coverage-targets-subset) echo feature/source-change ;;
    *) echo "feature/$1" ;;
  esac
}

scenario_ref() {
  case "$1" in
    no-baseline | stale-base | coverage-targets-subset) echo checkout/source-change ;;
    *) echo "checkout/$1" ;;
  esac
}

checkout() {
  local repo=$1 scenario=${2//_/-}
  local ref branch
  ref=$(scenario_ref "$scenario")
  branch=$(scenario_branch "$scenario")
  cd "$repo"
  git rev-parse -q --verify "refs/tags/$ref" >/dev/null || {
    echo "Unknown scenario: $2" >&2
    exit 1
  }
  git reset -q --hard
  git clean -fdq
  if [ -z "$branch" ]; then
    git checkout -q --detach "refs/tags/$ref"
  else
    git checkout -q -B "$branch" "refs/tags/$ref"
  fi
  if [ "$scenario" = dirty-checkout ]; then
    edit_discount
    write_featured
  fi
  git status --short
}

refs() {
  git -C "$1" for-each-ref --format='%(objectname) %(refname:short)' refs/heads refs/tags
}

# Fails when golden.json names a scenario, ref or branch the built history doesn't have.
check() {
  local repo=$1 kind value ref entries
  entries=$(python3 -I - "$fixture/golden.json" <<'PY'
import json, sys
for s in json.load(open(sys.argv[1]))["scenarios"]:
    checkout = s["checkout"]
    print("scenario", s["name"], checkout["ref"])
    for ref in [checkout["ref"]] + checkout.get("merge_parents", []) + [r["ref"] for r in s["runs"]]:
        print("ref", ref)
    for branch in [checkout["branch"]] + [r["branch"] for r in s["runs"]]:
        if branch:
            print("branch", branch)
PY
  )
  while read -r kind value ref; do
    case "$kind" in
      scenario) [ "$(scenario_ref "${value//_/-}")" = "$ref" ] || { echo "scenarios.sh doesn't check out $value at $ref" >&2; exit 1; } ;;
      ref) git -C "$repo" rev-parse -q --verify "refs/tags/$value" >/dev/null || { echo "Missing tag $value" >&2; exit 1; } ;;
      branch) git -C "$repo" rev-parse -q --verify "refs/heads/$value" >/dev/null || { echo "Missing branch $value" >&2; exit 1; } ;;
    esac
  done <<<"$entries"
  echo "golden.json matches $repo"
}

case "${1:-}" in
  build) [ $# -eq 3 ] || usage; build "$2" "$3" ;;
  checkout) [ $# -eq 3 ] || usage; checkout "$2" "$3" ;;
  refs) [ $# -eq 2 ] || usage; refs "$2" ;;
  check) [ $# -eq 2 ] || usage; check "$2" ;;
  *) usage ;;
esac
