import Testing
@testable import TuistSandboxCommand

struct SandboxSyncTests {
    @Test
    func entries_parseTheIndexListingAndSkipSubmodules() {
        let listing = [
            "100644 aaaa 0\tname with\ttab ",
            "160000 bbbb 0\tVendor/Submodule",
            "120000 cccc 0\tlink",
        ].map { $0 + "\0" }.joined()

        let entries = SandboxSync.entries(fromIndexListing: listing)

        #expect(entries == [
            SandboxSync.Entry(mode: "100644", object: "aaaa", path: "name with\ttab "),
            SandboxSync.Entry(mode: "120000", object: "cccc", path: "link"),
        ])
        #expect(SandboxSync.entries(SandboxSync.serialize(entries)) == entries)
    }

    @Test
    func changes_sendNewFilesAndThoseWhoseContentOrModeChanged() {
        let previous = [
            SandboxSync.Entry(mode: "100644", object: "1111", path: "same"),
            SandboxSync.Entry(mode: "100644", object: "2222", path: "edited"),
            SandboxSync.Entry(mode: "100644", object: "3333", path: "made-executable"),
            SandboxSync.Entry(mode: "100644", object: "4444", path: "deleted"),
        ]
        let current = [
            SandboxSync.Entry(mode: "100644", object: "1111", path: "same"),
            SandboxSync.Entry(mode: "100644", object: "2223", path: "edited"),
            SandboxSync.Entry(mode: "100755", object: "3333", path: "made-executable"),
            SandboxSync.Entry(mode: "100644", object: "5555", path: "added"),
        ]

        #expect(SandboxSync.changes(from: previous, to: current).map(\.path) == ["edited", "made-executable", "added"])
        #expect(SandboxSync.changes(from: nil, to: current) == current)
    }

    @Test
    func delta_listsThePathsThatLeftAndJoinedTheWorktree() {
        let previous = [
            SandboxSync.Entry(mode: "100644", object: "1111", path: "kept"),
            SandboxSync.Entry(mode: "100644", object: "2222", path: "a/b"),
            SandboxSync.Entry(mode: "100644", object: "3333", path: "edited"),
        ]
        let current = [
            SandboxSync.Entry(mode: "100644", object: "1111", path: "kept"),
            SandboxSync.Entry(mode: "100644", object: "4444", path: "a"),
            SandboxSync.Entry(mode: "100644", object: "3334", path: "edited"),
        ]

        let delta = SandboxSync.delta(from: previous, to: current)

        #expect(delta.deleted == ["a/b"])
        #expect(delta.added == ["a"])
    }

    @Test
    func shards_splitTheFilesInOrderIntoRunsOfAboutTheSameSize() {
        let mib = 1024 * 1024
        let even = (0 ..< 10).map { (path: "f\($0)", bytes: 4 * mib) }

        #expect(SandboxSync.shards(even, cores: 8) == [["f0", "f1"], ["f2", "f3"], ["f4", "f5"], ["f6", "f7"], ["f8", "f9"]])
        #expect(SandboxSync.shards(even, cores: 2) == [["f0", "f1", "f2", "f3", "f4"], ["f5", "f6", "f7", "f8", "f9"]])

        let skewed = [(path: "big", bytes: 100 * mib), (path: "a", bytes: mib), (path: "b", bytes: mib), (path: "c", bytes: mib)]
        #expect(SandboxSync.shards(skewed, cores: 4) == [["big"], ["a"], ["b"], ["c"]])

        let small = (0 ..< 3).map { (path: "s\($0)", bytes: 5 * mib) }
        #expect(SandboxSync.shards(small, cores: 8) == [["s0", "s1", "s2"]])

        let large = (0 ..< 100).map { (path: "l\($0)", bytes: 10 * mib) }
        let shards = SandboxSync.shards(large, cores: 16)
        #expect(shards.count == SandboxSync.maxShards)
        #expect(shards.flatMap { $0 } == large.map(\.path))
        #expect(SandboxSync.shards([], cores: 4) == [[]])
    }

    @Test
    func probe_readsTheRootAndTheWorktreeTheSandboxHolds() {
        #expect(SandboxSync.probe("root /home/u/work/app\nid abc\nprobed\n")! == ("/home/u/work/app", "abc"))
        #expect(SandboxSync.probe("root /home/u/work/app\nid \nprobed\n")! == ("/home/u/work/app", nil))
        #expect(SandboxSync.probe("mkdir: Permission denied\n") == nil)
    }
}
