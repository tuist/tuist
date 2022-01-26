if defined?(RSpec)
  shared_examples_for :packable_field do |field_klass|

    before(:all) do
      unless defined?(PackableFieldTest)
        class PackableFieldTest < ::Protobuf::Message; end
      end

      field_name = "#{field_klass.name.split('::').last.underscore}_packed_field".to_sym
      tag_num = PackableFieldTest.fields.size + 1
      PackableFieldTest.repeated(field_klass, field_name, tag_num, :packed => true)
    end

    let(:field_name) { "#{field_klass.name.split('::').last.underscore}_packed_field".to_sym }
    let(:value) { [100, 200, 300] }
    let(:message_instance) { PackableFieldTest.new(field_name => value) }

    subject { PackableFieldTest.get_field(field_name) }

    specify { expect(subject).to be_packed }
    specify { expect(PackableFieldTest.decode(message_instance.encode).send(field_name)).to eq value }
  end
end
