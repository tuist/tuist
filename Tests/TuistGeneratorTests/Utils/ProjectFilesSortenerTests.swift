//import Basic
//import Foundation
//import TuistSupport
//import XCTest
//
//@testable import TuistGenerator
//@testable import TuistSupportTesting
//
//final class ProjectFilesSortenerTests: TuistUnitTestCase {
//    var subject: ProjectFilesSortener!
//
//    override func setUp() {
//        super.setUp()
//        subject = ProjectFilesSortener()
//    }
//
//    override func tearDown() {
//        subject = nil
//        super.tearDown()
//    }
//
//    func test_sort_nestedGroups() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("path/to/A/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("path/to/A/B.swift")), group: .group(name: "Project"), isReference: false)
//        let file3 = GroupFileElement(path: basePath.appending(RelativePath("path/to/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file4 = GroupFileElement(path: basePath.appending(RelativePath("path/to/B.swift")), group: .group(name: "Project"), isReference: false)
//
//        let files = [file1, file2, file3, file4].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2, file3, file4])
//    }
//    
//    func test_sort_nestedGroupsCaseTwo() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("path/A/A/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("path/A/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file3 = GroupFileElement(path: basePath.appending(RelativePath("path/A/B.swift")), group: .group(name: "Project"), isReference: false)
//        let file4 = GroupFileElement(path: basePath.appending(RelativePath("path/Z/A/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file5 = GroupFileElement(path: basePath.appending(RelativePath("path/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file6 = GroupFileElement(path: basePath.appending(RelativePath("path/B.swift")), group: .group(name: "Project"), isReference: false)
//
//        let files = [file6, file2, file3, file4, file5, file1].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2, file3, file4, file5, file6])
//    }
//    
//    // TODO: change test names
//    func test_sort_nestedGroupsAndFolderReference() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("path/A/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("path/A/B.swift")), group: .group(name: "Project"), isReference: false)
//        let file3 = GroupFileElement(path: basePath.appending(RelativePath("path/B/README.md")), group: .group(name: "Project"), isReference: true)
//        let file4 = GroupFileElement(path: basePath.appending(RelativePath("path/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file5 = GroupFileElement(path: basePath.appending(RelativePath("path/B.swift")), group: .group(name: "Project"), isReference: false)
//        
//        let files = [file1, file2, file3, file4, file5].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2, file3, file4, file5])
//    }
//    
//    func test_sort_nestedGroupsAndRootPaths() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/README.md")), group: .group(name: "Project"), isReference: true)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("B/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file3 = GroupFileElement(path: basePath.appending(RelativePath("C.swift")), group: .group(name: "Project"), isReference: false)
//        let file4 = GroupFileElement(path: basePath.appending(RelativePath("D.swift")), group: .group(name: "Project"), isReference: false)
//        let file5 = GroupFileElement(path: basePath.appending(RelativePath("E.swift")), group: .group(name: "Project"), isReference: false)
//        let file6 = GroupFileElement(path: basePath.appending(RelativePath("F.swift")), group: .group(name: "Project"), isReference: false)
//        
//        let files = [file1, file2, file3, file4, file5, file6].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        XCTAssertEqual(got, [file1, file2, file3, file4, file5, file6])
//    }
//    
//    func test_sort_twoSeperateFoldersWithAllCases() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/ZZZZZZ.swift")), group: .group(name: "Project"), isReference: false)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("Z/AAAAAA.swift")), group: .group(name: "Project"), isReference: false)
//
//        let files = [file1, file2].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2])
//    }
//    
//    func test_sort_twoSeperateFoldersWithAllCases1() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/AAAAAA.swift")), group: .group(name: "Project"), isReference: false)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("A/ZZZZZZ.swift")), group: .group(name: "Project"), isReference: false)
//        
//
//        let files = [file1, file2].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2])
//    }
//    
//    func test_sort_twoSeperateFoldersWithAllCases2() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/A/AAAAAA.swift")), group: .group(name: "Project"), isReference: false)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("A/AAAAAA.swift")), group: .group(name: "Project"), isReference: false)
//        
//
//        let files = [file1, file2].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2])
//    }
//    
//    
//    func test_sort_twoSeperateFoldersWithAllCases3() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/A/AAAAAA.swift")), group: .group(name: "Project"), isReference: false)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("A/A/AAAAAA.swift")), group: .group(name: "Project"), isReference: false)
//        let file3 = GroupFileElement(path: basePath.appending(RelativePath("A/AAAAAA.swift")), group: .group(name: "Project"), isReference: false)
//        
//
//        let files = [file1, file2].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2])
//    }
//    
//    func test_sort_() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/A/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("A/B")), group: .group(name: "Project"), isReference: true)
//        let file3 = GroupFileElement(path: basePath.appending(RelativePath("A/C/A.swift")), group: .group(name: "Project"), isReference: false)
//
//        let files = [file1, file2, file3].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2, file3])
//    }
//    
//    func test_sort_lengthOfComponents() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/A/A")), group: .group(name: "Project"), isReference: true)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("A/B/A/A/A")), group: .group(name: "Project"), isReference: true)
//
//        let files = [file1, file2].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2])
//    }
//    
//    func test_sort_two() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/A")), group: .group(name: "Project"), isReference: true)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("A/A.swift")), group: .group(name: "Project"), isReference: false)
//
//        let files = [file1, file2].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2])
//    }
//    
//    func test_sort_three() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("A/A")), group: .group(name: "Project"), isReference: true)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("A/B")), group: .group(name: "Project"), isReference: true)
//        let file3 = GroupFileElement(path: basePath.appending(RelativePath("A/A.swift")), group: .group(name: "Project"), isReference: false)
//
//        let files = [file1, file2, file3].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2, file3])
//    }
//    
//    func test_sort_lotsOfFoldersBeforeFiles() throws {
//        // Given
//        let temporaryPath = try self.temporaryPath()
//        let basePath = temporaryPath
//        let file1 = GroupFileElement(path: basePath.appending(RelativePath("path/A/A")), group: .group(name: "Project"), isReference: true)
//        let file2 = GroupFileElement(path: basePath.appending(RelativePath("path/A/B")), group: .group(name: "Project"), isReference: true)
//        let file3 = GroupFileElement(path: basePath.appending(RelativePath("path/A/C")), group: .group(name: "Project"), isReference: true)
//        let file4 = GroupFileElement(path: basePath.appending(RelativePath("path/A/A.swift")), group: .group(name: "Project"), isReference: false)
//        let file5 = GroupFileElement(path: basePath.appending(RelativePath("path/A/B.swift")), group: .group(name: "Project"), isReference: false)
//        
//        let files = [file1, file2, file3, file4, file5].shuffled()
//        try files.forEach { try FileHandler.shared.touch($0.path) }
//
//        // When
//        let got = files.sorted(by: subject.sort)
//
//        // Then
//        printResults(files: got)
//        XCTAssertEqual(got, [file1, file2, file3, file4, file5])
//    }
//    
//    private func printResults(files: [GroupFileElement]) {
//        print("Final Order:")
//        for file in files {
//            print(file.path, file.isReference)
//        }
//    }
//}
