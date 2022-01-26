module Mocha
  # Allows setting of configuration options. See {Configuration} for the available options.
  #
  # Typically the configuration is set globally in a +test_helper.rb+ or +spec_helper.rb+ file.
  #
  # @see Configuration
  #
  # @yieldparam configuration [Configuration] the configuration for modification
  #
  # @example Setting multiple configuration options
  #   Mocha.configure do |c|
  #     c.stubbing_method_unnecessarily = :prevent
  #     c.stubbing_method_on_non_mock_object = :warn
  #     c.stubbing_method_on_nil = :allow
  #   end
  #
  def self.configure
    yield configuration
  end

  # @private
  def self.configuration
    Configuration.configuration
  end

  # This class provides a number of ways to configure the library.
  #
  # Typically the configuration is set globally in a +test_helper.rb+ or +spec_helper.rb+ file.
  #
  # @example Setting multiple configuration options
  #   Mocha.configure do |c|
  #     c.stubbing_method_unnecessarily = :prevent
  #     c.stubbing_method_on_non_mock_object = :warn
  #     c.stubbing_method_on_nil = :allow
  #   end
  #
  class Configuration
    # @private
    DEFAULTS = {
      :stubbing_method_unnecessarily => :allow,
      :stubbing_method_on_non_mock_object => :allow,
      :stubbing_non_existent_method => :allow,
      :stubbing_non_public_method => :allow,
      :stubbing_method_on_nil => :prevent,
      :display_matching_invocations_on_failure => false,
      :reinstate_undocumented_behaviour_from_v1_9 => true
    }.freeze

    attr_reader :options
    protected :options

    # @private
    def initialize(options = {})
      @options = DEFAULTS.merge(options)
    end

    # @private
    def initialize_copy(other)
      @options = other.options.dup
    end

    # @private
    def merge(other)
      self.class.new(@options.merge(other.options))
    end

    # Configure whether stubbing methods unnecessarily is allowed.
    #
    # This is useful for identifying unused stubs. Unused stubs are often accidentally introduced when code is {http://martinfowler.com/bliki/DefinitionOfRefactoring.html refactored}.
    #
    # When +value+ is +:allow+, do nothing. This is the default.
    # When +value+ is +:warn+, display a warning.
    # When +value+ is +:prevent+, raise a {StubbingError}.
    #
    # @param [Symbol] value one of +:allow+, +:warn+, +:prevent+.
    #
    # @example Preventing unnecessary stubbing of a method
    #   Mocha.configure do |c|
    #     c.stubbing_method_unnecessarily = :prevent
    #   end
    #
    #   example = mock('example')
    #   example.stubs(:unused_stub)
    #   # => Mocha::StubbingError: stubbing method unnecessarily:
    #   # =>   #<Mock:example>.unused_stub(any_parameters)
    #
    def stubbing_method_unnecessarily=(value)
      @options[:stubbing_method_unnecessarily] = value
    end

    # @private
    def stubbing_method_unnecessarily
      @options[:stubbing_method_unnecessarily]
    end

    # Configure whether stubbing methods on non-mock objects is allowed.
    #
    # If you like the idea of {http://www.jmock.org/oopsla2004.pdf mocking roles not objects} and {http://www.mockobjects.com/2007/04/test-smell-mocking-concrete-classes.html you don't like stubbing concrete classes}, this is the setting for you. However, while this restriction makes a lot of sense in Java with its {http://java.sun.com/docs/books/tutorial/java/concepts/interface.html explicit interfaces}, it may be moot in Ruby where roles are probably best represented as Modules.
    #
    # When +value+ is +:allow+, do nothing. This is the default.
    # When +value+ is +:warn+, display a warning.
    # When +value+ is +:prevent+, raise a {StubbingError}.
    #
    # @param [Symbol] value one of +:allow+, +:warn+, +:prevent+.
    #
    # @example Preventing stubbing of a method on a non-mock object
    #   Mocha.configure do |c|
    #     c.stubbing_method_on_non_mock_object = :prevent
    #   end
    #
    #   class Example
    #     def example_method; end
    #   end
    #
    #   example = Example.new
    #   example.stubs(:example_method)
    #   # => Mocha::StubbingError: stubbing method on non-mock object:
    #   # =>   #<Example:0x593620>.example_method
    #
    def stubbing_method_on_non_mock_object=(value)
      @options[:stubbing_method_on_non_mock_object] = value
    end

    # @private
    def stubbing_method_on_non_mock_object
      @options[:stubbing_method_on_non_mock_object]
    end

    # Configure whether stubbing of non-existent methods is allowed.
    #
    # This is useful if you want to ensure that methods you're mocking really exist. A common criticism of unit tests with mock objects is that such a test may (incorrectly) pass when an equivalent non-mocking test would (correctly) fail. While you should always have some integration tests, particularly for critical business functionality, this Mocha configuration setting should catch scenarios when mocked methods and real methods have become misaligned.
    #
    # When +value+ is +:allow+, do nothing. This is the default.
    # When +value+ is +:warn+, display a warning.
    # When +value+ is +:prevent+, raise a {StubbingError}.
    #
    # @param [Symbol] value one of +:allow+, +:warn+, +:prevent+.
    #
    # @example Preventing stubbing of a non-existent method
    #
    #   Mocha.configure do |c|
    #     c.stubbing_non_existent_method = :prevent
    #   end
    #
    #   class Example
    #   end
    #
    #   example = Example.new
    #   example.stubs(:method_that_doesnt_exist)
    #   # => Mocha::StubbingError: stubbing non-existent method:
    #   # =>   #<Example:0x593760>.method_that_doesnt_exist
    #
    def stubbing_non_existent_method=(value)
      @options[:stubbing_non_existent_method] = value
    end

    # @private
    def stubbing_non_existent_method
      @options[:stubbing_non_existent_method]
    end

    # Configure whether stubbing of non-public methods is allowed.
    #
    # Many people think that it's good practice only to mock public methods. This is one way to prevent your tests being too tightly coupled to the internal implementation of a class. Such tests tend to be very brittle and not much use when refactoring.
    #
    # When +value+ is +:allow+, do nothing. This is the default.
    # When +value+ is +:warn+, display a warning.
    # When +value+ is +:prevent+, raise a {StubbingError}.
    #
    # @param [Symbol] value one of +:allow+, +:warn+, +:prevent+.
    #
    # @example Preventing stubbing of a non-public method
    #   Mocha.configure do |c|
    #     c.stubbing_non_public_method = :prevent
    #   end
    #
    #   class Example
    #     def internal_method; end
    #     private :internal_method
    #   end
    #
    #   example = Example.new
    #   example.stubs(:internal_method)
    #   # => Mocha::StubbingError: stubbing non-public method:
    #   # =>   #<Example:0x593530>.internal_method
    #
    def stubbing_non_public_method=(value)
      @options[:stubbing_non_public_method] = value
    end

    # @private
    def stubbing_non_public_method
      @options[:stubbing_non_public_method]
    end

    # Configure whether stubbing methods on the +nil+ object is allowed.
    #
    # This is usually done accidentally, but there might be rare cases where it is intended.
    #
    # This option only works for Ruby < v2.2.0. In later versions of Ruby +nil+ is frozen and so a {StubbingError} will be raised if you attempt to stub a method on +nil+.
    #
    # When +value+ is +:allow+, do nothing.
    # When +value+ is +:warn+, display a warning.
    # When +value+ is +:prevent+, raise a {StubbingError}. This is the default.
    #
    # @param [Symbol] value one of +:allow+, +:warn+, +:prevent+.
    #
    def stubbing_method_on_nil=(value)
      @options[:stubbing_method_on_nil] = value
    end

    # @private
    def stubbing_method_on_nil
      @options[:stubbing_method_on_nil]
    end

    # Display matching invocations alongside expectations on Mocha-related test failure.
    #
    # @param [Boolean] value +true+ to enable display of matching invocations; disabled by default.
    #
    # @example Enable display of matching invocations
    #   Mocha.configure do |c|
    #     c.display_matching_invocations_on_failure = true
    #   end
    #
    #   foo = mock('foo')
    #   foo.expects(:bar)
    #   foo.stubs(:baz).returns('baz').raises(RuntimeError).throws(:tag, 'value')
    #
    #   foo.baz(1, 2)
    #   assert_raises(RuntimeError) { foo.baz(3, 4) }
    #   assert_throws(:tag) { foo.baz(5, 6) }
    #
    #   not all expectations were satisfied
    #   unsatisfied expectations:
    #   - expected exactly once, invoked never: #<Mock:foo>.bar
    #   satisfied expectations:
    #   - allowed any number of times, invoked 3 times: #<Mock:foo>.baz(any_parameters)
    #     - #<Mock:foo>.baz(1, 2) # => "baz"
    #     - #<Mock:foo>.baz(3, 4) # => raised RuntimeError
    #     - #<Mock:foo>.baz(5, 6) # => threw (:tag, "value")
    def display_matching_invocations_on_failure=(value)
      @options[:display_matching_invocations_on_failure] = value
    end

    # @private
    def display_matching_invocations_on_failure?
      @options[:display_matching_invocations_on_failure]
    end

    # Reinstate undocumented behaviour from v1.9
    #
    # Previously when {API#mock}, {API#stub}, or {API#stub_everything} were called with the first argument being a symbol, they built an *unnamed* mock object *and* expected or stubbed the method identified by the symbol argument; subsequent arguments were ignored.
    # Now these methods build a *named* mock with the name specified by the symbol argument; *no* methods are expected or stubbed and subsequent arguments *are* taken into account.
    #
    # Previously if {Expectation#yields} or {Expectation#multiple_yields} was called on an expectation, but no block was given when the method was invoked, the instruction to yield was ignored.
    # Now a +LocalJumpError+ is raised.
    #
    # Enabling this configuration option reinstates the previous behaviour, but displays a deprecation warning.
    #
    # @param [Boolean] value +true+ to reinstate undocumented behaviour; enabled by default.
    #
    # @example Reinstate undocumented behaviour for {API#mock}
    #   Mocha.configure do |c|
    #     c.reinstate_undocumented_behaviour_from_v1_9 = true
    #   end
    #
    #   foo = mock(:bar)
    #   foo.inspect # => #<Mock>
    #
    #   not all expectations were satisfied
    #   unsatisfied expectations:
    #   - expected exactly once, invoked never: #<Mock>.foo
    #
    # @example Reinstate undocumented behaviour for {API#stub}
    #   Mocha.configure do |c|
    #     c.reinstate_undocumented_behaviour_from_v1_9 = true
    #   end
    #
    #   foo = stub(:bar)
    #   foo.inspect # => #<Mock>
    #   foo.bar # => nil
    #
    # @example Reinstate undocumented behaviour for {Expectation#yields}
    #   foo = mock('foo')
    #   foo.stubs(:my_method).yields(1, 2)
    #   foo.my_method # => raises LocalJumpError when no block is supplied
    #
    #   Mocha.configure do |c|
    #     c.reinstate_undocumented_behaviour_from_v1_9 = true
    #   end
    #
    #   foo = mock('foo')
    #   foo.stubs(:my_method).yields(1, 2)
    #   foo.my_method # => does *not* raise LocalJumpError when no block is supplied
    #
    def reinstate_undocumented_behaviour_from_v1_9=(value)
      @options[:reinstate_undocumented_behaviour_from_v1_9] = value
    end

    # @private
    def reinstate_undocumented_behaviour_from_v1_9?
      @options[:reinstate_undocumented_behaviour_from_v1_9]
    end

    class << self
      # Allow the specified +action+.
      #
      # @param [Symbol] action one of +:stubbing_method_unnecessarily+, +:stubbing_method_on_non_mock_object+, +:stubbing_non_existent_method+, +:stubbing_non_public_method+, +:stubbing_method_on_nil+.
      # @yield optional block during which the configuration change will be changed before being returned to its original value at the end of the block.
      # @deprecated If a block is supplied, call {.override} with a +Hash+ containing an entry with the +action+ as the key and +:allow+ as the value. If no block is supplied, call the appropriate +action+ writer method with +value+ set to +:allow+ via {Mocha.configure}. The writer method will be the one of the following corresponding to the +action+:
      #   * {#stubbing_method_unnecessarily=}
      #   * {#stubbing_method_on_non_mock_object=}
      #   * {#stubbing_non_existent_method=}
      #   * {#stubbing_non_public_method=}
      #   * {#stubbing_method_on_nil=}
      def allow(action, &block)
        if block_given?
          Deprecation.warning("Use Mocha::Configuration.override(#{action}: :allow) with the same block")
        else
          Deprecation.warning("Use Mocha.configure { |c| c.#{action} = :allow }")
        end
        change_config action, :allow, &block
      end

      # @private
      def allow?(action)
        configuration.allow?(action)
      end

      # Warn if the specified +action+ is attempted.
      #
      # @param [Symbol] action one of +:stubbing_method_unnecessarily+, +:stubbing_method_on_non_mock_object+, +:stubbing_non_existent_method+, +:stubbing_non_public_method+, +:stubbing_method_on_nil+.
      # @yield optional block during which the configuration change will be changed before being returned to its original value at the end of the block.
      # @deprecated If a block is supplied, call {.override} with a +Hash+ containing an entry with the +action+ as the key and +:warn+ as the value. If no block is supplied, call the appropriate +action+ writer method with +value+ set to +:warn+ via {Mocha.configure}. The writer method will be the one of the following corresponding to the +action+:
      #   * {#stubbing_method_unnecessarily=}
      #   * {#stubbing_method_on_non_mock_object=}
      #   * {#stubbing_non_existent_method=}
      #   * {#stubbing_non_public_method=}
      #   * {#stubbing_method_on_nil=}
      def warn_when(action, &block)
        if block_given?
          Deprecation.warning("Use Mocha::Configuration.override(#{action}: :warn) with the same block")
        else
          Deprecation.warning("Use Mocha.configure { |c| c.#{action} = :warn }")
        end
        change_config action, :warn, &block
      end

      # @private
      def warn_when?(action)
        configuration.warn_when?(action)
      end

      # Raise a {StubbingError} if the specified +action+ is attempted.
      #
      # @param [Symbol] action one of +:stubbing_method_unnecessarily+, +:stubbing_method_on_non_mock_object+, +:stubbing_non_existent_method+, +:stubbing_non_public_method+, +:stubbing_method_on_nil+.
      # @yield optional block during which the configuration change will be changed before being returned to its original value at the end of the block.
      # @deprecated If a block is supplied, call {.override} with a +Hash+ containing an entry with the +action+ as the key and +:prevent+ as the value. If no block is supplied, call the appropriate +action+ writer method with +value+ set to +:prevent+ via {Mocha.configure}. The writer method will be the one of the following corresponding to the +action+:
      #   * {#stubbing_method_unnecessarily=}
      #   * {#stubbing_method_on_non_mock_object=}
      #   * {#stubbing_non_existent_method=}
      #   * {#stubbing_non_public_method=}
      #   * {#stubbing_method_on_nil=}
      def prevent(action, &block)
        if block_given?
          Deprecation.warning("Use Mocha::Configuration.override(#{action}: :prevent) with the same block")
        else
          Deprecation.warning("Use Mocha.configure { |c| c.#{action} = :prevent }")
        end
        change_config action, :prevent, &block
      end

      # @private
      def prevent?(action)
        configuration.prevent?(action)
      end

      # @private
      def reset_configuration
        @configuration = nil
      end

      # Temporarily modify {Configuration} options.
      #
      # The supplied +temporary_options+ will override the current configuration for the duration of the supplied block.
      # The configuration will be returned to its original state when the block returns.
      #
      # @param [Hash] temporary_options the configuration options to apply for the duration of the block.
      # @yield block during which the configuration change will be in force.
      #
      # @example Temporarily allow stubbing of +nil+
      #   Mocha::Configuration.override(stubbing_method_on_nil: :allow) do
      #     nil.stubs(:foo)
      #   end
      def override(temporary_options)
        original_configuration = configuration
        @configuration = configuration.merge(new(temporary_options))
        yield
      ensure
        @configuration = original_configuration
      end

      # @private
      def configuration
        @configuration ||= new
      end

      private

      # @private
      def change_config(action, new_value, &block)
        if block_given?
          temporarily_change_config action, new_value, &block
        else
          configuration.send("#{action}=".to_sym, new_value)
        end
      end

      # @private
      def temporarily_change_config(action, new_value)
        original_configuration = configuration
        new_configuration = configuration.dup
        new_configuration.send("#{action}=".to_sym, new_value)
        @configuration = new_configuration
        yield
      ensure
        @configuration = original_configuration
      end
    end
  end
end
