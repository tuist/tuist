module Protobuf
  class Error < StandardError; end
  class InvalidWireType < Error; end
  class NotInitializedError < Error; end
  class TagCollisionError < Error; end
  class SerializationError < StandardError; end
  class FieldNotDefinedError < StandardError; end
  class DuplicateFieldNameError < StandardError; end
end
