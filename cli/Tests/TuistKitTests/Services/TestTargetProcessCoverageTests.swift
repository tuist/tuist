import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
@testable import TuistKit

struct TestTargetProcessCoverageTests {
    @Test func readsTheFunctionsThatRanOffASparseTextProfile() {
        let text = """
        # IR level Instrumentation Flag
        :fe
        $s4Core3addyS2i_SitF
        # Func Hash:
        24
        # Num Counters:
        1
        # Counter Values:
        3

        Core.m:helper
        # Func Hash:
        1
        # Num Counters:
        1
        # Counter Values:
        1
        """

        #expect(TestTargetProcessCoverage.functionReferences(profileText: text) == [
            CoverageObserverOutput.nameReference("$s4Core3addyS2i_SitF"),
            CoverageObserverOutput.nameReference("Core.m:helper"),
        ])
    }

    @Test func keepsTheFilesWhoseCodeRanWithTheLinesThatRan() {
        let report = """
        SF:/src/Core.swift
        FN:2,add
        FNDA:3,add
        DA:2,3
        DA:3,0
        DA:4,1
        end_of_record
        SF:/src/Unused.swift
        FN:1,never
        FNDA:0,never
        DA:1,0
        end_of_record
        SF:/src/Header.h
        FN:1,inlineOnly
        FNDA:2,inlineOnly
        end_of_record
        """

        #expect(TestTargetProcessCoverage.executedLines(lcov: report) == [
            "/src/Core.swift": IndexSet([2, 4]),
            "/src/Header.h": IndexSet(),
        ])
    }

    @Test(.inTemporaryDirectory) func readsOnlyTheRunsOwnRawProfiles() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let old = directory.appending(component: "A-1.profraw")
        FileManager.default.createFile(atPath: old.pathString, contents: Data())
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.pathString)
        let runStartedAt = Date(timeIntervalSinceNow: -60)
        for name in ["B-2.profraw", "Coverage.profdata"] {
            FileManager.default.createFile(atPath: directory.appending(component: name).pathString, contents: Data())
        }

        #expect(TestTargetProcessCoverage.rawProfiles(in: directory, createdAfter: runStartedAt) == [
            directory.appending(component: "B-2.profraw"),
        ])
    }
}
