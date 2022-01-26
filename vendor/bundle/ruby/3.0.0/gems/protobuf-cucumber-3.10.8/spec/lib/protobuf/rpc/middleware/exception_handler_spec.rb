require 'spec_helper'

RSpec.describe Protobuf::Rpc::Middleware::ExceptionHandler do
  let(:app) { proc { |env| env } }
  let(:env) { Protobuf::Rpc::Env.new }

  subject { described_class.new(app) }

  describe "#call" do
    it "calls the stack" do
      expect(app).to receive(:call).with(env)
      subject.call(env)
    end

    it "returns the env" do
      expect(subject.call(env)).to eq env
    end

    context "when exceptions occur" do
      let(:encoded_error) { error.encode }
      let(:error) { Protobuf::Rpc::MethodNotFound.new('Boom!') }

      before { allow(app).to receive(:call).and_raise(error, 'Boom!') }

      it "rescues exceptions" do
        expect { subject.call(env) }.not_to raise_exception
      end

      context "when exception is a Protobuf error" do
        it "does not wrap the exception in a generic Protobuf error" do
          stack_env = subject.call(env)

          # Can't compare the error instances because the response has been
          # raised and thus has a backtrace while the error does not.
          expect(stack_env.response.class).to eq error.class
        end

        it "encodes the response" do
          stack_env = subject.call(env)
          expect(stack_env.encoded_response).to eq encoded_error
        end
      end

      context "when exception is not a Protobuf error" do
        let(:encoded_error) { error.encode }
        let(:error) { Protobuf::Rpc::RpcFailed.new('Boom!') }

        before { allow(app).to receive(:call).and_raise(RuntimeError, 'Boom!') }

        it "wraps the exception in a generic Protobuf error" do
          stack_env = subject.call(env)
          expect(stack_env.response).to eq error
        end

        it "encodes the wrapped exception" do
          stack_env = subject.call(env)
          expect(stack_env.encoded_response).to eq encoded_error
        end
      end
    end
  end
end
