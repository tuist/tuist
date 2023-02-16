import ApolloAPI

public typealias ID = String

public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
    where Schema == TuistCloudSchema.SchemaMetadata {}

public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
    where Schema == TuistCloudSchema.SchemaMetadata {}

public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
    where Schema == TuistCloudSchema.SchemaMetadata {}

public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
    where Schema == TuistCloudSchema.SchemaMetadata {}

public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
    public static let configuration: ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

    public static func objectType(forTypename typename: String) -> Object? {
        switch typename {
        case "Mutation": return TuistCloudSchema.Objects.Mutation
        case "CreateProject": return TuistCloudSchema.Objects.CreateProject
        case "Project": return TuistCloudSchema.Objects.Project
        case "UserError": return TuistCloudSchema.Objects.UserError
        default: return nil
        }
    }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
