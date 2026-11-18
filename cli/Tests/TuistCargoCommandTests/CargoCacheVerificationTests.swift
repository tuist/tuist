import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistREAPI

@testable import TuistCargoCommand

struct CargoCacheVerificationTests {
    @Test func samplesTheSameUnitsInEveryCheckout() throws {
        let arguments = { (root: String) in
            [
                "rustc",
                "--crate-name",
                "serde",
                "--edition=2021",
                "\(root)/src/lib.rs",
                "--crate-type",
                "lib",
                "--cfg",
                "feature=\"std\"",
            ]
        }
        let first = CargoCacheVerification.identity(
            arguments("/a/serde"), environment: ["CARGO_MANIFEST_DIR": "/a/serde", "CARGO_PKG_NAME": "serde"],
            directory: try AbsolutePath(validating: "/a/serde")
        )
        // The same package in a checkout at another path, compiled from its directory with a relative source.
        let moved = CargoCacheVerification.identity(
            [
                "rustc",
                "--crate-name",
                "serde",
                "--edition=2021",
                "src/lib.rs",
                "--crate-type",
                "lib",
                "--cfg",
                "feature=\"std\"",
            ],
            environment: ["CARGO_MANIFEST_DIR": "/elsewhere/serde", "CARGO_PKG_NAME": "serde"],
            directory: try AbsolutePath(validating: "/elsewhere/serde")
        )
        #expect(first == moved)
        // Cargo compiles a workspace member from the workspace root, naming its source relative to that root.
        let member = CargoCacheVerification.identity(
            arguments("crates/serde"), environment: ["CARGO_MANIFEST_DIR": "/ws/crates/serde", "CARGO_PKG_NAME": "serde"],
            directory: try AbsolutePath(validating: "/ws")
        )
        #expect(member == first)
        let other = CargoCacheVerification.identity(
            arguments("/a/serde").map { $0 == "feature=\"std\"" ? "feature=\"alloc\"" : $0 },
            environment: ["CARGO_MANIFEST_DIR": "/a/serde", "CARGO_PKG_NAME": "serde"],
            directory: try AbsolutePath(validating: "/a/serde")
        )
        #expect(first != other)
    }

    @Test func samplesOneUnitInSixtyFourByIdentity() {
        let identities = (0 ..< 6400).map { "crate-\($0)" }
        let selected = identities.filter { CargoCacheVerification.selects(.sampled, identity: $0) }
        // 100 expected; a counter that restarts in every hook would select all of them, a constant none.
        #expect((60 ... 150).contains(selected.count))
        #expect(identities.allSatisfy { CargoCacheVerification.selects(.always, identity: $0) })
        #expect(!identities.contains { CargoCacheVerification.selects(.off, identity: $0) })
    }

    @Test func staysOffUnlessAskedFor() {
        #expect(CargoCacheVerification.mode(nil) == .off)
        #expect(CargoCacheVerification.mode("0") == .off)
        #expect(CargoCacheVerification.mode("off") == .off)
        #expect(CargoCacheVerification.mode(" Sampled ") == .sampled)
        #expect(CargoCacheVerification.mode("ALWAYS") == .always)
        #expect(CargoCacheVerification.mode("1") == .always)
        #expect(!CargoCacheVerification.selection(identity: "x", environment: [:]).any)
        let both = CargoCacheVerification.selection(
            identity: "x", environment: ["TUIST_CARGO_VERIFY": "always", "TUIST_CARGO_VERIFY_RECOMPILE": "off"]
        )
        #expect(both.inputs && !both.outputs)
    }

    @Test func readsTheKeyDidNotNameDiverge() {
        func set(_ paths: String...) -> CargoReadSet {
            CargoReadSet(entries: paths.map { .init(kind: "path", name: $0) })
        }
        let unkeyed = CargoCacheVerification.compare(used: set("@@TUIST_WORKSPACE@@/a.rs"), fresh: set(
            "@@TUIST_WORKSPACE@@/a.rs", "@@TUIST_WORKSPACE@@/b.rs"
        ))
        #expect(unkeyed.outcome == .unkeyed)
        #expect(unkeyed.divergent)
        #expect(unkeyed.detail.contains("b.rs"))
        // A key naming more than the run read only misses more often; it never serves a stale hit.
        let narrower = CargoCacheVerification.compare(
            used: set("@@TUIST_WORKSPACE@@/a.rs", "@@TUIST_WORKSPACE@@/b.rs"), fresh: set("@@TUIST_WORKSPACE@@/a.rs")
        )
        #expect(narrower.outcome == .narrower)
        #expect(!narrower.divergent)
        // An environment variable is a read like a file.
        let variable = CargoCacheVerification.compare(
            used: set("@@TUIST_WORKSPACE@@/a.rs"),
            fresh: CargoReadSet(entries: [
                .init(kind: "path", name: "@@TUIST_WORKSPACE@@/a.rs"),
                .init(kind: "env", name: "HOME"),
            ])
        )
        #expect(variable.outcome == .unkeyed)
        #expect(CargoCacheVerification.compare(used: set("x"), fresh: set("x")).outcome == .match)
    }

    @Test func classifiesEveryDifferenceOutsideLinkEditDataAsContent() {
        func classify(_ cached: String, _ fresh: String) -> CargoCacheVerification.Finding.Outcome {
            CargoCacheVerification.classify(cached: Data(cached.utf8), fresh: Data(fresh.utf8)).0
        }
        #expect(classify("value 1", "value 1") == .match)
        // A key binds every machine root its outputs name, so a correct hit differs from a fresh compilation in no path.
        // Values that look like paths, such as dates, git refs, URLs and search paths, change what a build does.
        let differences = [
            ("src @@TUIST_WORKSPACE@@/src/lib.rs:1", "src /Users/me/checkout/src/lib.rs:1"),
            ("cargo:rustc-env=BUILD_DATE=2026/11/16\n", "cargo:rustc-env=BUILD_DATE=2026/11/17\n"),
            ("\u{0F}refs/heads/main", "\u{0F}refs/heads/dev1"),
            ("let url = \"/v1/x\";", "let url = \"/v2/x\";"),
            ("cargo:rustc-link-search=native=/opt/homebrew/lib/v3", "cargo:rustc-link-search=native=/opt/homebrew/lib/v4"),
            ("const VALUE: u8 = 1;", "const VALUE: u8 = 2;"),
        ]
        for (cached, fresh) in differences {
            #expect(classify(cached, fresh) == .content, "\(cached) against \(fresh)")
        }
        let (_, detail) = CargoCacheVerification.classify(cached: Data("abc1".utf8), fresh: Data("abc2".utf8))
        #expect(detail.contains("byte 3"))
    }

    @Test func checksSourcesWithARunThatWritesOnlyDepInfo() {
        let arguments = CargoCacheVerification.dependencyInfoArguments(
            [
                "/toolchain/bin/rustc", "--crate-name", "x", "--edition=2021", "src/lib.rs", "--emit=dep-info,metadata,link",
                "--emit", "link", "-C", "incremental=/t/incremental/x", "-Cincremental=/t/i", "--out-dir", "/t/deps",
                "-C", "opt-level=0",
            ],
            depInfo: "/tmp/verify/inputs.d", remap: ["--remap-path-prefix=/ws="]
        )
        #expect(arguments == [
            "--crate-name", "x", "--edition=2021", "src/lib.rs", "--out-dir", "/t/deps", "-C", "opt-level=0",
            "--emit=dep-info=/tmp/verify/inputs.d", "--remap-path-prefix=/ws=",
        ])
    }

    @Test func ignoresOnlyTheLinkEditDataOfMachOImages() {
        func image(text: UInt8, uuid: UInt8, linkEdit: UInt8) -> Data {
            func le(_ value: some FixedWidthInteger) -> [UInt8] { withUnsafeBytes(of: value.littleEndian, Array.init) }
            var bytes: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE] + le(UInt32(0x0100_000C)) + le(UInt32(0)) + le(UInt32(2))
                + le(UInt32(2)) + le(UInt32(96)) + le(UInt32(0)) + le(UInt32(0))
            let name = Array("__LINKEDIT".utf8) + [UInt8](repeating: 0, count: 6)
            bytes += le(UInt32(0x19)) + le(UInt32(72)) + name + le(UInt64(0)) + le(UInt64(32)) + le(UInt64(160))
                + le(UInt64(32)) + le(UInt32(1)) + le(UInt32(1)) + le(UInt32(0)) + le(UInt32(0))
            bytes += le(UInt32(0x1B)) + le(UInt32(24)) + [UInt8](repeating: uuid, count: 16)
            bytes += [UInt8](repeating: text, count: 32) + [UInt8](repeating: linkEdit, count: 32)
            return Data(bytes)
        }
        let cached = image(text: 0x01, uuid: 0x01, linkEdit: 0x01)
        let relinked = CargoCacheVerification.classify(cached: cached, fresh: image(text: 0x01, uuid: 0x02, linkEdit: 0x02))
        #expect(relinked.0 == .pathDebug)
        let changed = CargoCacheVerification.classify(cached: cached, fresh: image(text: 0x02, uuid: 0x02, linkEdit: 0x02))
        #expect(changed.0 == .content)
    }

    @Test func contentOutweighsPathDifferences() {
        let finding = CargoCacheVerification.summarize([
            ("libx.rmeta", .pathDebug, ""), ("libx.rlib", .content, "first difference at byte 9"), ("x.d", .match, ""),
        ])
        #expect(finding.outcome == .content)
        #expect(finding.detail == "content: libx.rlib (first difference at byte 9); path-debug: libx.rmeta")
        #expect(CargoCacheVerification.summarize([("x.d", .match, "")]).outcome == .match)
    }

    @Test(.inTemporaryDirectory) func countsBuildScriptRunsAsVerificationTasksWithoutMisses() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        let environment = ["TUIST_CARGO_SESSION": root.path]
        let key = REAPI.digest(Data("run".utf8))
        CargoCacheMeasurement.verified(name: "clock build script run", key: key, divergent: true, environment: environment)
        CargoCacheMeasurement.verified(name: "gen build script run", key: key, divergent: false, environment: environment)
        let metrics = try #require(CargoCacheReport.read(root: root))
        // `verifications` counts as task misses, and a restored run is never counted as a hit.
        #expect(metrics["verifications"] as? UInt64 == 0)
        #expect(metrics["divergences"] as? UInt64 == 1)
        #expect(metrics["hits"] as? UInt64 == 0)
        let tasks = try #require((metrics["details"] as? [String: Any])?["tasks"] as? [[String: Any]])
        #expect(tasks.compactMap { $0["status"] as? String } == ["verification", "verification"])
        #expect(metrics["details"].flatMap { ($0 as? [String: Any])?["truncated"] as? Bool } == false)
    }
}
