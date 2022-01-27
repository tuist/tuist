require File.expand_path("../../setup", __FILE__)
require "middleware"

describe Middleware::Runner do
  it "should work with an empty stack" do
    instance = described_class.new([])
    expect { instance.call({}) }.to_not raise_error
  end

  it "should call classes in the proper order" do
    a = Class.new do
      def initialize(app)
        @app = app
      end

      def call(env)
        env[:result] << "A"
        @app.call(env)
        env[:result] << "A"
      end
    end

    b = Class.new do
      def initialize(app)
        @app = app
      end

      def call(env)
        env[:result] << "B"
        @app.call(env)
        env[:result] << "B"
      end
    end

    env = { :result => [] }
    instance = described_class.new([a, b])
    instance.call(env)
    env[:result].should == ["A", "B", "B", "A"]
  end

  it "should call lambdas in the proper order" do
    data = []
    a = lambda { |env| data << "A" }
    b = lambda { |env| data << "B" }

    instance = described_class.new([a, b])
    instance.call({})

    data.should == ["A", "B"]
  end

  it "passes in arguments if given" do
    a = Class.new do
      def initialize(app, value)
        @app   = app
        @value = value
      end

      def call(env)
        env[:result] = @value
      end
    end

    env = {}
    instance = described_class.new([[a, 42]])
    instance.call(env)

    env[:result].should == 42
  end

  it "passes in a block if given" do
    a = Class.new do
      def initialize(app, &block)
        @block = block
      end

      def call(env)
        env[:result] = @block.call
      end
    end

    block = Proc.new { 42 }
    env = {}
    instance = described_class.new([[a, nil, block]])
    instance.call(env)

    env[:result].should == 42
  end

  it "should raise an error if an invalid middleware is given" do
    expect { described_class.new([27]) }.to
      raise_error
  end
end
