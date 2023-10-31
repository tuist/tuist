# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

class ActiveModel::Errors
  Elem = type_member { { fixed: ActiveModel::Error } }

  sig { params(attribute: T.any(Symbol, String)).returns(T::Array[String]) }
  def [](attribute); end

  sig { params(attribute: T.any(Symbol, String), type: T.untyped, options: T.untyped).returns(ActiveModel::Error) }
  def add(attribute, type = :invalid, **options); end

  sig { params(attribute: T.any(Symbol, String), type: T.untyped, options: T.untyped).returns(T::Boolean) }
  def added?(attribute, type = :invalid, options = {}); end

  sig { params(options: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
  def as_json(options = nil); end

  sig { returns(T::Array[Symbol]) }
  def attribute_names; end

  sig { params(attribute: T.any(Symbol, String), type: T.untyped, options: T.untyped).returns(T.nilable(T::Array[String])) }
  def delete(attribute, type = nil, **options); end

  sig { returns(T::Hash[Symbol, T::Array[T::Hash[Symbol, T.untyped]]]) }
  def details; end

  sig { returns(T::Array[Elem]) }
  def errors; end

  sig { params(attribute: T.any(Symbol, String), message: String).returns(String) }
  def full_message(attribute, message); end

  sig { returns(T::Array[String]) }
  def full_messages; end

  sig { params(attribute: T.any(Symbol, String)).returns(T::Array[String]) }
  def full_messages_for(attribute); end

  sig { params(attribute: T.any(Symbol, String), type: T.untyped, options: T.untyped).returns(String) }
  def generate_message(attribute, type = :invalid, options = {}); end

  sig { returns(T::Hash[Symbol, T::Array[ActiveModel::Error]]) }
  def group_by_attribute; end

  sig { params(attribute: T.any(Symbol, String)).returns(T::Boolean) }
  def has_key?(attribute); end

  sig { params(error: ActiveModel::Error, override_options: T.untyped).returns(T::Array[ActiveModel::Error]) }
  def import(error, override_options = {}); end

  sig { params(attribute: T.any(Symbol, String)).returns(T::Boolean) }
  def include?(attribute); end

  sig { params(attribute: T.any(Symbol, String)).returns(T::Boolean) }
  def key?(attribute); end

  sig { params(other: T.untyped).returns(T::Array[ActiveModel::Error]) }
  def merge!(other); end

  sig { returns(T::Hash[Symbol, T::Array[String]]) }
  def messages; end

  sig { params(attribute: T.any(Symbol, String)).returns(T::Array[String]) }
  def messages_for(attribute); end

  sig { returns(T::Array[Elem]) }
  def objects; end

  sig { params(attribute: T.any(Symbol, String), type: T.untyped).returns(T::Boolean) }
  def of_kind?(attribute, type = :invalid); end

  sig { returns(T::Array[String]) }
  def to_a; end

  sig { params(full_messages: T.untyped).returns(T::Hash[Symbol, T::Array[String]]) }
  def to_hash(full_messages = false); end

  sig { params(attribute: T.any(Symbol, String), type: T.untyped, options: T.untyped).returns(T::Array[ActiveModel::Error]) }
  def where(attribute, type = nil, **options); end
end

module ActiveModel::Validations
  sig { returns(ActiveModel::Errors) }
  def errors; end
end
