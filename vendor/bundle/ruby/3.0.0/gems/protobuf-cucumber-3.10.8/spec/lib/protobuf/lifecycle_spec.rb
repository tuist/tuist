require 'spec_helper'
require 'protobuf/lifecycle'

RSpec.describe ::Protobuf::Lifecycle do
  subject { described_class }

  around do |example|
    # this entire class is deprecated
    ::Protobuf.deprecator.silence(&example)
  end

  before do
    ::ActiveSupport::Notifications.notifier = ::ActiveSupport::Notifications::Fanout.new
  end

  it "registers a string as the event_name" do
    expect(::ActiveSupport::Notifications).to receive(:subscribe).with("something")
    subject.register("something") { true }
  end

  it "only registers blocks for event callbacks" do
    expect do
      subject.register("something")
    end.to raise_error(/block/)
  end

  it "calls the registered block when triggered" do
    this = nil
    subject.register("this") do
      this = "not nil"
    end

    subject.trigger("this")
    expect(this).to_not be_nil
    expect(this).to eq("not nil")
  end

  it "calls multiple registered blocks when triggered" do
    this = nil
    that = nil

    subject.register("this") do
      this = "not nil"
    end

    subject.register("this") do
      that = "not nil"
    end

    subject.trigger("this")
    expect(this).to_not be_nil
    expect(this).to eq("not nil")
    expect(that).to_not be_nil
    expect(that).to eq("not nil")
  end

  context 'when the registered block has arity' do
    context 'and the triggered event does not have args' do
      it 'does not pass the args' do
        outer_bar = nil

        subject.register('foo') do |bar|
          expect(bar).to be_nil
          outer_bar = 'triggered'
        end

        subject.trigger('foo')
        expect(outer_bar).to eq 'triggered'
      end
    end

    context 'and the triggered event has arguments' do
      it 'does not pass the args' do
        outer_bar = nil

        subject.register('foo') do |bar|
          expect(bar).to_not be_nil
          outer_bar = bar
        end

        subject.trigger('foo', 'baz')
        expect(outer_bar).to eq 'baz'
      end
    end
  end

  context "normalized event names" do
    specify { expect(subject.normalized_event_name(:derp)).to eq("derp") }
    specify { expect(subject.normalized_event_name(:Derp)).to eq("derp") }
    specify { expect(subject.normalized_event_name("DERP")).to eq("derp") }
    specify { expect(subject.normalized_event_name("derp")).to eq("derp") }
  end

end
