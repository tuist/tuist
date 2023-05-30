@_exported import ApolloAPI
import TuistCloudSchema

public class ClearRemoteCacheStorageMutation: GraphQLMutation {
    public static let operationName: String = "ClearRemoteCacheStorage"
    public static let document: ApolloAPI.DocumentType = .notPersisted(
        definition: .init(
            """
            mutation ClearRemoteCacheStorage($input: ClearRemoteCacheStorageInput!) {
              clearRemoteCacheStorage(input: $input) {
                __typename
                bucket {
                  __typename
                  id
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

    public var input: TuistCloudSchema.ClearRemoteCacheStorageInput

    public init(input: TuistCloudSchema.ClearRemoteCacheStorageInput) {
        self.input = input
    }

    public var __variables: Variables? { ["input": input] }

    public struct Data: TuistCloudSchema.SelectionSet {
        public let __data: DataDict
        public init(data: DataDict) { __data = data }

        public static var __parentType: ParentType { TuistCloudSchema.Objects.Mutation }
        public static var __selections: [Selection] { [
            .field("clearRemoteCacheStorage", ClearRemoteCacheStorage.self, arguments: ["input": .variable("input")]),
        ] }

        /// Clears the remote cache storage
        public var clearRemoteCacheStorage: ClearRemoteCacheStorage { __data["clearRemoteCacheStorage"] }

        /// ClearRemoteCacheStorage
        ///
        /// Parent Type: `ClearRemoteCacheStorage`
        public struct ClearRemoteCacheStorage: TuistCloudSchema.SelectionSet {
            public let __data: DataDict
            public init(data: DataDict) { __data = data }

            public static var __parentType: ParentType { TuistCloudSchema.Objects.ClearRemoteCacheStorage }
            public static var __selections: [Selection] { [
                .field("bucket", Bucket?.self),
                .field("errors", [Error].self),
            ] }

            public var bucket: Bucket? { __data["bucket"] }
            public var errors: [Error] { __data["errors"] }

            /// ClearRemoteCacheStorage.Bucket
            ///
            /// Parent Type: `S3Bucket`
            public struct Bucket: TuistCloudSchema.SelectionSet {
                public let __data: DataDict
                public init(data: DataDict) { __data = data }

                public static var __parentType: ParentType { TuistCloudSchema.Objects.S3Bucket }
                public static var __selections: [Selection] { [
                    .field("id", TuistCloudSchema.ID.self),
                ] }

                public var id: TuistCloudSchema.ID { __data["id"] }
            }

            /// ClearRemoteCacheStorage.Error
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
