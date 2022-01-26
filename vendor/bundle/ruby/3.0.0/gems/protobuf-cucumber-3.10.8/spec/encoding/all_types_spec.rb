require 'spec_helper'
require PROTOS_PATH.join('google_unittest.pb')

RSpec.describe ::Protobuf do
  it "correctly encodes all types" do
    message = Protobuf_unittest::TestAllTypes.new(
      :optional_int32 => 101,
      :optional_int64 => 102,
      :optional_uint32 => 103,
      :optional_uint64 => 104,
      :optional_sint32 => 105,
      :optional_sint64 => 106,
      :optional_fixed32 => 107,
      :optional_fixed64 => 108,
      :optional_sfixed32 => 109,
      :optional_sfixed64 => 110,
      :optional_float => 111,
      :optional_double => 112,
      :optional_bool => true,
      :optional_string => "115",
      :optional_bytes => "116".force_encoding(Encoding::ASCII_8BIT),
      :optional_nested_message => Protobuf_unittest::TestAllTypes::NestedMessage.new(:bb => 118),
      :optional_foreign_message => Protobuf_unittest::ForeignMessage.new(:c => 119),
      :optional_import_message => Protobuf_unittest_import::ImportMessage.new(:d => 120),
      :optional_nested_enum => Protobuf_unittest::TestAllTypes::NestedEnum::BAZ,
      :optional_foreign_enum => Protobuf_unittest::ForeignEnum::FOREIGN_BAZ,
      :optional_import_enum => Protobuf_unittest_import::ImportEnum::IMPORT_BAZ,
      :optional_string_piece => "124",
      :optional_cord => "125",
      :optional_public_import_message => Protobuf_unittest_import::PublicImportMessage.new(:e => 126),
      :optional_lazy_message => Protobuf_unittest::TestAllTypes::NestedMessage.new(:bb => 127),
      :repeated_int32 => [201, 301],
      :repeated_int64 => [202, 302],
      :repeated_uint32 => [203, 303],
      :repeated_uint64 => [204, 304],
      :repeated_sint32 => [205, 305],
      :repeated_sint64 => [206, 306],
      :repeated_fixed32 => [207, 307],
      :repeated_fixed64 => [208, 308],
      :repeated_sfixed32 => [209, 309],
      :repeated_sfixed64 => [210, 310],
      :repeated_float => [211, 311],
      :repeated_double => [212, 312],
      :repeated_bool => [true, false],
      :repeated_string => ["215", "315"],
      :repeated_bytes => ["216".force_encoding(Encoding::ASCII_8BIT), "316".force_encoding(Encoding::ASCII_8BIT)],
      :repeated_nested_message => [
        ::Protobuf_unittest::TestAllTypes::NestedMessage.new(:bb => 218),
        ::Protobuf_unittest::TestAllTypes::NestedMessage.new(:bb => 318),
      ],
      :repeated_foreign_message => [
        ::Protobuf_unittest::ForeignMessage.new(:c => 219),
        ::Protobuf_unittest::ForeignMessage.new(:c => 319),
      ],
      :repeated_import_message => [
        ::Protobuf_unittest_import::ImportMessage.new(:d => 220),
        ::Protobuf_unittest_import::ImportMessage.new(:d => 320),
      ],
      :repeated_nested_enum => [
        ::Protobuf_unittest::TestAllTypes::NestedEnum::BAR,
        ::Protobuf_unittest::TestAllTypes::NestedEnum::BAZ,
      ],
      :repeated_foreign_enum => [
        ::Protobuf_unittest::ForeignEnum::FOREIGN_BAR,
        ::Protobuf_unittest::ForeignEnum::FOREIGN_BAZ,
      ],
      :repeated_import_enum => [
        ::Protobuf_unittest_import::ImportEnum::IMPORT_BAR,
        ::Protobuf_unittest_import::ImportEnum::IMPORT_BAZ,
      ],
      :repeated_string_piece => ["224", "324"],
      :repeated_cord => ["225", "325"],
      :repeated_lazy_message => [
        ::Protobuf_unittest::TestAllTypes::NestedMessage.new(:bb => 227),
        ::Protobuf_unittest::TestAllTypes::NestedMessage.new(:bb => 327),
      ],
      :default_int32 => 401,
      :default_int64 => 402,
      :default_uint32 => 403,
      :default_uint64 => 404,
      :default_sint32 => 405,
      :default_sint64 => 406,
      :default_fixed32 => 407,
      :default_fixed64 => 408,
      :default_sfixed32 => 409,
      :default_sfixed64 => 410,
      :default_float => 411,
      :default_double => 412,
      :default_bool => false,
      :default_string => "415",
      :default_bytes => "416".force_encoding(Encoding::ASCII_8BIT),
      :default_nested_enum => ::Protobuf_unittest::TestAllTypes::NestedEnum::FOO,
      :default_foreign_enum => ::Protobuf_unittest::ForeignEnum::FOREIGN_FOO,
      :default_import_enum => ::Protobuf_unittest_import::ImportEnum::IMPORT_FOO,
      :default_string_piece => "424",
      :default_cord => "425",
    )

    data_file_path = PROTOS_PATH.join('all_types.data.bin')
    data = File.open(data_file_path, 'rb', &:read)
    expect(data).to eq(message.serialize_to_string)
  end
end
