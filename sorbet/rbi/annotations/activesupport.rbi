# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

module ActiveSupport::Testing::Declarative
  sig { params(name: String, block: T.proc.bind(T.untyped).void).void }
  def test(name, &block); end
end

class ActiveSupport::EnvironmentInquirer
  sig { returns(T::Boolean) }
  def development?; end

  sig { returns(T::Boolean) }
  def production?; end

  sig { returns(T::Boolean) }
  def test?; end

  # @method_missing: delegated to String through ActiveSupport::StringInquirer
  sig { returns(T::Boolean) }
  def staging?; end
end

module ActiveSupport::Testing::SetupAndTeardown::ClassMethods
  sig { params(args: T.untyped, block: T.nilable(T.proc.bind(T.untyped).void)).void }
  def setup(*args, &block); end

  sig { params(args: T.untyped, block: T.nilable(T.proc.bind(T.untyped).void)).void }
  def teardown(*args, &block); end
end

class ActiveSupport::TestCase
  sig { params(args: T.untyped, block: T.nilable(T.proc.bind(T.attached_class).void)).void }
  def self.setup(*args, &block); end

  sig { params(args: T.untyped, block: T.nilable(T.proc.bind(T.attached_class).void)).void }
  def self.teardown(*args, &block); end

  sig { params(name: String, block: T.proc.bind(T.attached_class).void).void }
  def self.test(name, &block); end
end

class ActiveSupport::TimeWithZone
  # @shim: Methods on ActiveSupport::TimeWithZone are delegated to `Time` using `method_missing
  include ::DateAndTime::Zones

  # @shim: Methods on ActiveSupport::TimeWithZone are delegated to `Time` using `method_missing
  include ::DateAndTime::Calculations

  sig { returns(FalseClass) }
  def blank?; end

  # @shim: since `present?` is always true, `presence` always returns `self`
  sig { returns(T.self_type) }
  def presence; end

  # @shim: since `blank?` is always false, `present?` always returns `true`
  sig { returns(TrueClass) }
  def present?; end
end

class Object
  sig { returns(T::Boolean) }
  def blank?; end

  sig { returns(FalseClass) }
  def html_safe?; end

  sig { returns(T.nilable(T.self_type)) }
  def presence; end

  sig { params(another_object: T.untyped).returns(T.nilable(T.self_type)) }
  def presence_in(another_object); end

  sig { returns(T::Boolean) }
  def present?; end
end

class Hash
  sig { returns(T::Boolean) }
  def extractable_options?; end
end

class Array
  sig { params(position: Integer).returns(T.self_type) }
  def from(position); end

  sig { params(position: Integer).returns(T.self_type) }
  def to(position); end

  sig { params(elements: T.untyped).returns(T::Array[T.untyped]) }
  def including(*elements); end

  sig { params(elements: T.untyped).returns(T.self_type) }
  def excluding(*elements); end

  sig { params(elements: T.untyped).returns(T.self_type) }
  def without(*elements); end

  sig { returns(T.nilable(Elem)) }
  def second; end

  sig { returns(T.nilable(Elem)) }
  def third; end

  sig { returns(T.nilable(Elem)) }
  def fourth; end

  sig { returns(T.nilable(Elem)) }
  def fifth; end

  sig { returns(T.nilable(Elem)) }
  def forty_two; end

  sig { returns(T.nilable(Elem)) }
  def third_to_last; end

  sig { returns(T.nilable(Elem)) }
  def second_to_last; end

  sig { params(options: T::Hash[T.untyped, T.untyped]).returns(String) }
  def to_sentence(options = {}); end

  sig { params(format: Symbol).returns(String) }
  def to_fs(format = :default); end

  sig { params(format: Symbol).returns(String) }
  def to_formatted_s(format = :default); end

  sig { returns(String) }
  def to_xml; end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def extract_options!; end

  sig { type_parameters(:FillType).params(number: Integer, fill_with: T.type_parameter(:FillType), block: T.nilable(T.proc.params(group: T::Array[T.any(Elem, T.type_parameter(:FillType))]).void)).returns(T::Array[T::Array[T.any(Elem, T.type_parameter(:FillType))]]) }
  def in_groups(number, fill_with = T.unsafe(nil), &block); end

  sig { type_parameters(:FillType).params(number: Integer, fill_with: T.type_parameter(:FillType), block: T.nilable(T.proc.params(group: T::Array[T.any(Elem, T.type_parameter(:FillType))]).void)).returns(T::Array[T::Array[T.any(Elem, T.type_parameter(:FillType))]]) }
  def in_groups_of(number, fill_with = T.unsafe(nil), &block); end

  sig { params(value: T.untyped, block: T.nilable(T.proc.params(element: Elem).returns(T.untyped))).returns(T::Array[T::Array[Elem]]) }
  def split(value = nil, &block); end

  sig { params(block: T.nilable(T.proc.params(element: Elem).returns(T.untyped))).returns(T.any(T::Array[Elem], T::Enumerator[Elem])) }
  def extract!(&block); end

  sig { returns(ActiveSupport::ArrayInquirer) }
  def inquiry; end

  sig { params(object: T.untyped).returns(T::Array[T.untyped]) }
  def self.wrap(object); end
end

class Date
  sig { returns(FalseClass) }
  def blank?; end

  # @shim: since `present?` is always true, `presence` always returns `self`
  sig { returns(T.self_type) }
  def presence; end

  # @shim: since `blank?` is always false, `present?` always returns `true`
  sig { returns(TrueClass) }
  def present?; end
end

class DateTime
  sig { returns(FalseClass) }
  def blank?; end

  # @shim: since `present?` is always true, `presence` always returns `self`
  sig { returns(T.self_type) }
  def presence; end

  # @shim: since `blank?` is always false, `present?` always returns `true`
  sig { returns(TrueClass) }
  def present?; end
end

class NilClass
  sig { returns(TrueClass) }
  def blank?; end

  # @shim: since `present?` is always false, `presence` always returns `nil`
  sig { returns(NilClass) }
  def presence; end

  # @shim: since `blank?` is always true, `present?` always returns `false`
  sig { returns(FalseClass) }
  def present?; end
end

class FalseClass
  sig { returns(TrueClass) }
  def blank?; end

  # @shim: since `present?` is always false, `presence` always returns `nil`
  sig { returns(NilClass) }
  def presence; end

  # @shim: since `blank?` is always true, `present?` always returns `false`
  sig { returns(FalseClass) }
  def present?; end
end

class TrueClass
  sig { returns(FalseClass) }
  def blank?; end

  # @shim: since `present?` is always true, `presence` always returns `self`
  sig { returns(T.self_type) }
  def presence; end

  # @shim: since `blank?` is always false, `present?` always returns `true`
  sig { returns(TrueClass) }
  def present?; end
end

class Numeric
  sig { returns(FalseClass) }
  def blank?; end

  sig { returns(TrueClass) }
  def html_safe?; end

  # @shim: since `present?` is always true, `presence` always returns `self`
  sig { returns(T.self_type) }
  def presence; end

  # @shim: since `blank?` is always false, `present?` always returns `true`
  sig { returns(TrueClass) }
  def present?; end
end

class Time
  sig { returns(FalseClass) }
  def blank?; end

  # @shim: since `present?` is always true, `presence` always returns `self`
  sig { returns(T.self_type) }
  def presence; end

  # @shim: since `blank?` is always false, `present?` always returns `true`
  sig { returns(TrueClass) }
  def present?; end
end

class Symbol
  # alias for `#start_with?`
  sig { params(string_or_regexp: T.any(String, Regexp)).returns(T::Boolean) }
  def starts_with?(*string_or_regexp); end

  # alias for `#end_with?`
  sig { params(string_or_regexp: T.any(String, Regexp)).returns(T::Boolean) }
  def ends_with?(*string_or_regexp); end
end

class String
  sig { returns(TrueClass) }
  def acts_like_string?; end

  sig { params(position: Integer).returns(T.nilable(String)) }
  sig { params(position: T.any(T::Range[Integer], Regexp)).returns(T.nilable(String)) }
  sig { params(position: String).returns(T.nilable(String)) }
  def at(position); end

  sig { returns(String) }
  def as_json; end

  sig { returns(T::Boolean) }
  def blank?; end

  sig { params(first_letter: Symbol).returns(String) }
  def camelcase(first_letter = :upper); end

  sig { params(first_letter: Symbol).returns(String) }
  def camelize(first_letter = :upper); end

  sig { returns(String) }
  def classify; end

  sig { returns(T.untyped) }
  def constantize; end

  sig { returns(String) }
  def dasherize; end

  sig { returns(String) }
  def deconstantize; end

  sig { returns(String) }
  def demodulize; end

  # alias for `#end_with?`
  sig { params(string_or_regexp: T.any(String, Regexp)).returns(T::Boolean) }
  def ends_with?(*string_or_regexp); end

  sig { returns(String) }
  def downcase_first; end

  sig { params(string: String).returns(T::Boolean) }
  def exclude?(string); end

  sig { params(limit: Integer).returns(String) }
  def first(limit = 1); end

  sig { params(separate_class_name_and_id_with_underscore: T::Boolean).returns(String) }
  def foreign_key(separate_class_name_and_id_with_underscore = true); end

  sig { params(position: Integer).returns(String) }
  def from(position); end

  sig { returns(ActiveSupport::SafeBuffer) }
  def html_safe; end

  sig { params(capitalize: T::Boolean, keep_id_suffix: T::Boolean).returns(String) }
  def humanize(capitalize: true, keep_id_suffix: false); end

  sig { params(zone: T.nilable(T.any(ActiveSupport::TimeZone, String))).returns(T.any(ActiveSupport::TimeWithZone, Time)) }
  def in_time_zone(zone = ::Time.zone); end

  sig { params(amount: Integer, indent_string: T.nilable(String), indent_empty_lines: T::Boolean).returns(String) }
  def indent(amount, indent_string = nil, indent_empty_lines = false); end

  sig { params(amount: Integer, indent_string: T.nilable(String), indent_empty_lines: T::Boolean).returns(T.nilable(String)) }
  def indent!(amount, indent_string = nil, indent_empty_lines = false); end

  sig { returns(ActiveSupport::StringInquirer) }
  def inquiry; end

  sig { returns(T::Boolean) }
  def is_utf8?; end

  sig { params(limit: Integer).returns(String) }
  def last(limit = 1); end

  sig { returns(ActiveSupport::Multibyte::Chars) }
  def mb_chars; end

  sig { params(separator: String, preserve_case: T::Boolean, locale: T.nilable(Symbol)).returns(String) }
  def parameterize(separator: "-", preserve_case: false, locale: nil); end

  sig { params(count: T.nilable(T.any(Integer, Symbol)), locale: T.nilable(Symbol)).returns(String) }
  def pluralize(count = nil, locale = :en); end

  sig { params(patterns: T.any(String, Regexp)).returns(String) }
  def remove(*patterns); end

  sig { params(patterns: T.any(String, Regexp)).returns(String) }
  def remove!(*patterns); end

  sig { returns(T.untyped) }
  def safe_constantize; end

  sig { params(locale: Symbol).returns(String) }
  def singularize(locale = :en); end

  sig { returns(String) }
  def squish; end

  sig { returns(String) }
  def squish!; end

  # alias for `#start_with?`
  sig { params(string_or_regexp: T.any(String, Regexp)).returns(T::Boolean) }
  def starts_with?(*string_or_regexp); end

  sig { returns(String) }
  def strip_heredoc; end

  sig { returns(String) }
  def tableize; end

  sig { params(keep_id_suffix: T::Boolean).returns(String) }
  def titlecase(keep_id_suffix: false); end

  sig { params(keep_id_suffix: T::Boolean).returns(String) }
  def titleize(keep_id_suffix: false); end

  sig { params(position: Integer).returns(String) }
  def to(position); end

  sig { returns(::Date) }
  def to_date; end

  sig { returns(::DateTime) }
  def to_datetime; end

  sig { params(form: T.nilable(Symbol)).returns(T.nilable(Time)) }
  def to_time(form = :local); end

  sig { params(truncate_to: Integer, options: T::Hash[Symbol, T.anything]).returns(String) }
  def truncate(truncate_to, options = {}); end

  sig { params(truncate_to: Integer, omission: T.nilable(String)).returns(String) }
  def truncate_bytes(truncate_to, omission: "…"); end

  sig { params(words_count: Integer, options: T::Hash[Symbol, T.anything]).returns(String) }
  def truncate_words(words_count, options = {}); end

  sig { returns(String) }
  def underscore; end

  sig { returns(String) }
  def upcase_first; end
end

class ActiveSupport::ErrorReporter
  sig { type_parameters(:Block, :Fallback).params(error_classes: T.class_of(Exception), severity: T.nilable(Symbol), context: T.nilable(T::Hash[Symbol, T.untyped]), fallback: T.nilable(T.proc.returns(T.type_parameter(:Fallback))), source: T.nilable(String), blk: T.proc.returns(T.type_parameter(:Block))).returns(T.any(T.type_parameter(:Block), T.type_parameter(:Fallback))) }
  def handle(*error_classes, severity: T.unsafe(nil), context: T.unsafe(nil), fallback: T.unsafe(nil), source: T.unsafe(nil), &blk); end

  sig { type_parameters(:Block).params(error_classes: T.class_of(Exception), severity: T.nilable(Symbol), context: T.nilable(T::Hash[Symbol, T.untyped]), source: T.nilable(String), blk: T.proc.returns(T.type_parameter(:Block))).returns(T.type_parameter(:Block)) }
  def record(*error_classes, severity: T.unsafe(nil), context: T.unsafe(nil), source: T.unsafe(nil), &blk); end

  sig { params(error: Exception, handled: T::Boolean, severity: T.nilable(Symbol), context: T::Hash[Symbol, T.untyped], source: T.nilable(String)).void }
  def report(error, handled: true, severity: T.unsafe(nil), context: T.unsafe(nil), source: T.unsafe(nil)); end
end
