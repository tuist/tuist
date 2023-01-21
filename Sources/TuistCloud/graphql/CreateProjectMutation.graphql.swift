@_exported import ApolloAPI
import TuistCloudSchema

public class CreateProjectMutation: GraphQLMutation {
    public static let operationName: String = "CreateProject"
    public static let document: DocumentType = .notPersisted(
        definition: .init(
            """
            mutation CreateProject($input: CreateProjectInput!) {
              createProject(input: $input) {
                __typename
                project {
                  __typename
                  slug
                }
                errors {
                  __typename
                  message
                  path
                }
              }
            }
            """
        )
    )

    public var input: TuistCloudSchema.CreateProjectInput

    public init(input: TuistCloudSchema.CreateProjectInput) {
        self.input = input
    }

    public var __variables: Variables? { ["input": input] }

    public struct Data: TuistCloudSchema.SelectionSet {
        public let __data: DataDict
        public init(data: DataDict) { __data = data }

        public static var __parentType: ParentType { TuistCloudSchema.Objects.Mutation }
        public static var __selections: [Selection] { [
            .field("createProject", CreateProject.self, arguments: ["input": .variable("input")]),
        ] }

        /// Creates a new project
        public var createProject: CreateProject { __data["createProject"] }

        /// CreateProject
        ///
        /// Parent Type: `CreateProject`
        public struct CreateProject: TuistCloudSchema.SelectionSet {
            public let __data: DataDict
            public init(data: DataDict) { __data = data }

            public static var __parentType: ParentType { TuistCloudSchema.Objects.CreateProject }
            public static var __selections: [Selection] { [
                .field("project", Project?.self),
                .field("errors", [Error].self),
            ] }

            public var project: Project? { __data["project"] }
            public var errors: [Error] { __data["errors"] }

            /// CreateProject.Project
            ///
            /// Parent Type: `Project`
            public struct Project: TuistCloudSchema.SelectionSet {
                public let __data: DataDict
                public init(data: DataDict) { __data = data }

                public static var __parentType: ParentType { TuistCloudSchema.Objects.Project }
                public static var __selections: [Selection] { [
                    .field("slug", String.self),
                ] }

                public var slug: String { __data["slug"] }
            }

            /// CreateProject.Error
            ///
            /// Parent Type: `UserError`
            public struct Error: TuistCloudSchema.SelectionSet {
                public let __data: DataDict
                public init(data: DataDict) { __data = data }

                public static var __parentType: ParentType { TuistCloudSchema.Objects.UserError }
                public static var __selections: [Selection] { [
                    .field("message", String.self),
                    .field("path", [String]?.self),
                ] }

                /// A description of the error
                public var message: String { __data["message"] }
                /// Which input value this error came from
                public var path: [String]? { __data["path"] }
            }
        }
    }
}
