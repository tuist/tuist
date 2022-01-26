require 'cucumber/wire/configuration'
require 'tempfile'

module Cucumber
  module Wire
    describe Configuration do
      let(:wire_file) { Tempfile.new('wire') }
      let(:config) { Configuration.from_file(wire_file.path) }

      def write_wire_file(contents)
        wire_file << contents
        wire_file.close
      end

      it "reads the hostname / port from the file" do
        write_wire_file %q{
          host: localhost
          port: 54321
        }

        expect(config.host).to eq 'localhost'
        expect(config.port).to eq 54321
      end

      it "reads the timeout for a specific message" do
        write_wire_file %q{
          host: localhost
          port: 54321
          timeout:
            invoke: 99
        }

        expect(config.timeout('invoke')).to eq 99
      end

      it "reads the timeout for a connect message" do
        write_wire_file %q{
          host: localhost
          port: 54321
          timeout:
            connect: 99
        }

        expect(config.timeout('connect')).to eq 99
      end

      describe "a wire file with no timeouts specified" do
        before(:each) do
          write_wire_file %q{
            host: localhost
            port: 54321
          }
        end

        %w(invoke begin_scenario end_scenario).each do |message|
          it "sets the default timeout for '#{message}' to 120 seconds" do
            expect(config.timeout(message)).to eq 120
          end
        end
      end
    end
  end
end
