# frozen_string_literal: true

module ActionView
  module Helpers
    module Tags # :nodoc:
      class Translator # :nodoc:
        def initialize(object, object_name, method_and_value, scope:)
          @object_name = object_name.gsub(/\[(.*)_attributes\]\[\d+\]/, '.\1')
          @method_and_value = method_and_value
          @scope = scope
          @model = object.respond_to?(:to_model) ? object.to_model : nil
        end

        def translate
          translated_attribute = I18n.t("#{object_name}.#{method_and_value}", default: i18n_default, scope: scope).presence
          translated_attribute || human_attribute_name
        end

        private
          attr_reader :object_name, :method_and_value, :scope, :model

          def i18n_default
            if model
              key = model.model_name.i18n_key
              ["#{key}.#{method_and_value}".to_sym, ""]
            else
              ""
            end
          end

          def human_attribute_name
            if model && model.class.respond_to?(:human_attribute_name)
              model.class.human_attribute_name(method_and_value)
            end
          end
      end
    end
  end
end
