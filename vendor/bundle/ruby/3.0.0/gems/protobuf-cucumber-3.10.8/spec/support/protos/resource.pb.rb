# encoding: utf-8

##
# This file is auto-generated. DO NOT EDIT!
#
require 'protobuf'
require 'protobuf/rpc/service'


##
# Imports
#
require 'google/protobuf/descriptor.pb'

module Test
  ::Protobuf::Optionable.inject(self) { ::Google::Protobuf::FileOptions }

  ##
  # Enum Classes
  #
  class StatusType < ::Protobuf::Enum
    set_option :allow_alias, true
    set_option :".test.enum_option", -789

    define :PENDING, 0
    define :ENABLED, 1
    define :DISABLED, 2
    define :DELETED, 3
    define :ALIASED, 3
  end


  ##
  # Message Classes
  #
  class ResourceFindRequest < ::Protobuf::Message; end
  class ResourceSleepRequest < ::Protobuf::Message; end
  class Resource < ::Protobuf::Message; end
  class ResourceWithRequiredField < ::Protobuf::Message; end
  class Searchable < ::Protobuf::Message
    class SearchType < ::Protobuf::Enum
      define :FLAT, 1
      define :NESTED, 2
    end

  end

  class MessageParent < ::Protobuf::Message
    class MessageChild < ::Protobuf::Message; end

  end

  class Nested < ::Protobuf::Message
    class NestedLevelOne < ::Protobuf::Message; end

  end



  ##
  # File Options
  #
  set_option :cc_generic_services, true
  set_option :".test.file_option", 9876543210


  ##
  # Message Fields
  #
  class ResourceFindRequest
    required :string, :name, 1
    optional :bool, :active, 2
    repeated :string, :widgets, 3
    repeated :bytes, :widget_bytes, 4
    optional :bytes, :single_bytes, 5
  end

  class ResourceSleepRequest
    optional :int32, :sleep, 1
  end

  class Resource
    # Message Options
    set_option :map_entry, false
    set_option :".test.message_option", -56

    required :string, :name, 1, :ctype => ::Google::Protobuf::FieldOptions::CType::CORD, :".test.field_option" => 8765432109
    optional :int64, :date_created, 2
    optional ::Test::StatusType, :status, 3
    repeated ::Test::StatusType, :repeated_enum, 4
    # Extension Fields
    extensions 100...536870912
    optional :bool, :".test.Searchable.ext_is_searchable", 100, :extension => true
    optional :bool, :".test.Searchable.ext_is_hidden", 101, :extension => true
    optional ::Test::Searchable::SearchType, :".test.Searchable.ext_search_type", 102, :default => ::Test::Searchable::SearchType::FLAT, :extension => true
    optional :bool, :".test.Nested.NestedLevelOne.ext_nested_in_level_one", 105, :extension => true
    optional :bool, :".test.Nested.NestedLevelOne.ext_dup_field", 106, :extension => true
  end

  class ResourceWithRequiredField
    required :string, :foo_is_required, 1
  end

  class MessageParent
    class MessageChild
      optional :string, :child1, 1
    end

  end

  class Nested
    class NestedLevelOne
      optional :bool, :level_one, 1, :default => true
      # Extension Fields
      extensions 100...102
      optional :bool, :".test.ext_nested_level_one_outer", 101, :extension => true
      optional :bool, :".test.Nested.ext_nested_level_one", 100, :extension => true
    end

    optional :string, :name, 1
    optional ::Test::Resource, :resource, 2
    repeated ::Test::Resource, :multiple_resources, 3
    optional ::Test::StatusType, :status, 4
    # Extension Fields
    extensions 100...111
    optional :string, :".test.foo", 100, :extension => true
    optional :int64, :".test.bar", 101, :extension => true
  end


  ##
  # Extended Message Fields
  #
  class ::Google::Protobuf::FileOptions < ::Protobuf::Message
    optional :uint64, :".test.file_option", 9585869, :extension => true
  end

  class ::Google::Protobuf::FieldOptions < ::Protobuf::Message
    optional :uint64, :".test.field_option", 858769, :extension => true
  end

  class ::Google::Protobuf::EnumOptions < ::Protobuf::Message
    optional :int64, :".test.enum_option", 590284, :extension => true
  end

  class ::Google::Protobuf::MessageOptions < ::Protobuf::Message
    optional :int64, :".test.message_option", 485969, :extension => true
  end

  class ::Google::Protobuf::ServiceOptions < ::Protobuf::Message
    optional :int64, :".test.service_option", 5869607, :extension => true
  end

  class ::Google::Protobuf::MethodOptions < ::Protobuf::Message
    optional :int64, :".test.method_option", 7893233, :extension => true
  end


  ##
  # Service Classes
  #
  class ResourceService < ::Protobuf::Rpc::Service
    set_option :".test.service_option", -9876543210
    rpc :find, ::Test::ResourceFindRequest, ::Test::Resource do
      set_option :".test.method_option", 2
    end
    rpc :find_with_rpc_failed, ::Test::ResourceFindRequest, ::Test::Resource
    rpc :find_with_sleep, ::Test::ResourceSleepRequest, ::Test::Resource
    rpc :find_not_implemented, ::Test::ResourceFindRequest, ::Test::Resource
  end

end
