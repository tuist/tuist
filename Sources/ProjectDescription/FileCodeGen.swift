import Foundation

/// FileCodeGen: Soure file code generation attribues
///
/// - `public`:  public codegen attribute  `settings = {ATTRIBUTES = (codegen, )`}
/// - `private`:  private codegen attribute  `settings = {ATTRIBUTES = (private_codegen, )}`
/// - `project`:  project codegen attribute  `settings = {ATTRIBUTES = (project_codegen, )}`
/// - `disabled`:  disabled codegen attribute  `settings = {ATTRIBUTES = (no_codegen, )}`
///
public enum FileCodeGen: String, Codable, Equatable {
    case `public`
    case `private`
    case project
    case disabled
}
