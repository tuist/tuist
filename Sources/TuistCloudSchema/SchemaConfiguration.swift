import ApolloAPI

public enum SchemaConfiguration: ApolloAPI.SchemaConfiguration {
    public static func cacheKeyInfo(for _: Object, object _: JSONObject) -> CacheKeyInfo? {
        // Implement this function to configure cache key resolution for your schema types.
        nil
    }
}
