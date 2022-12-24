# frozen_string_literal: true

class TuistCloudSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  class << self
    # Union and Interface Resolution
    def resolve_type(abstract_type, obj, ctx)
      # TODO: Implement this function
      # to return the correct object type for `obj`
      raise(GraphQL::RequiredImplementationMissingError)
    end

    # Relay-style Object Identification:

    # Return a string UUID for `object`
    def id_from_object(object, type_definition, query_ctx)
      # Here's a simple implementation which:
      # - joins the type name & object.id
      # - encodes it with base64:
      # GraphQL::Schema::UniqueWithinType.encode(type_definition.name, object.id)
    end

    # Given a string UUID, find the object
    def object_from_id(id, query_ctx)
      # For example, to decode the UUIDs generated above:
      # type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
      #
      # Then, based on `type_name` and `id`
      # find an object in your application
      # ...
    end
  end
end
