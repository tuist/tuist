# typed: true

# DO NOT EDIT MANUALLY
# This file was pulled from a central RBI files repository.
# Please run `bin/tapioca annotations` to update it.

module ActionView
  TemplateError = T.type_alias { Template::Error }

  class MissingTemplate < ActionView::ActionViewError
    sig { returns(String) }
    def path; end
  end
end

class ActionView::Helpers::FormBuilder
  sig { returns(T.untyped) }
  def object; end
end

module ActionView::Helpers::NumberHelper
  sig { params(number: T.untyped, options: T::Hash[T.untyped, T.untyped]).returns(T.nilable(String)) }
  def number_to_currency(number, options = T.unsafe(nil)); end

  sig { params(number: T.untyped, options: T::Hash[T.untyped, T.untyped]).returns(T.nilable(String)) }
  def number_to_human(number, options = T.unsafe(nil)); end

  sig { params(number: T.untyped, options: T::Hash[T.untyped, T.untyped]).returns(T.nilable(String)) }
  def number_to_human_size(number, options = T.unsafe(nil)); end

  sig { params(number: T.untyped, options: T::Hash[T.untyped, T.untyped]).returns(T.nilable(String)) }
  def number_to_percentage(number, options = T.unsafe(nil)); end

  sig { params(number: T.untyped, options: T::Hash[T.untyped, T.untyped]).returns(T.nilable(String)) }
  def number_to_phone(number, options = T.unsafe(nil)); end

  sig { params(number: T.untyped, options: T::Hash[T.untyped, T.untyped]).returns(T.nilable(String)) }
  def number_with_delimiter(number, options = T.unsafe(nil)); end

  sig { params(number: T.untyped, options: T::Hash[T.untyped, T.untyped]).returns(T.nilable(String)) }
  def number_with_precision(number, options = T.unsafe(nil)); end
end

module ActionView::Helpers::SanitizeHelper
  mixes_in_class_methods ActionView::Helpers::SanitizeHelper::ClassMethods
end

module ActionView::Helpers::UrlHelper
  extend ActiveSupport::Concern
  include ActionView::Helpers::TagHelper
  mixes_in_class_methods ActionView::Helpers::UrlHelper::ClassMethods

  sig { params(name: T.nilable(String), options: T.untyped, html_options: T.untyped, block: T.untyped).returns(ActiveSupport::SafeBuffer) }
  def link_to(name = nil, options = nil, html_options = nil, &block); end

  sig { params(condition: T.untyped, name: String, options: T.untyped, html_options: T.untyped, block: T.untyped).returns(T.untyped) }
  def link_to_if(condition, name, options = {}, html_options = {}, &block); end
end

module ActionView::Layouts
  mixes_in_class_methods ActionView::Layouts::ClassMethods
end

module ActionView::Rendering
  mixes_in_class_methods ActionView::Rendering::ClassMethods
end

module ActionView::ViewPaths
  mixes_in_class_methods ActionView::ViewPaths::ClassMethods
end

module ActionView::ViewPaths::ClassMethods
  sig { params(value: T.any(String, T::Array[String])).void }
  def append_view_path(value); end
end
