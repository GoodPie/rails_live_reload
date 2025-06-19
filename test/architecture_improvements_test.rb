# frozen_string_literal: true

require "test_helper"

class ArchitectureImprovementsTest < ActiveSupport::TestCase
  def setup
    # Reset the container for each test
    RailsLiveReload.reset!
  end

  def teardown
    # Clean up after each test
    RailsLiveReload.reset!
  end

  test "dependency injection container works correctly" do
    container = RailsLiveReload::Container.new

    # Test service registration
    container.register(:test_service) { "test_value" }
    assert_equal "test_value", container.resolve(:test_service)

    # Test singleton registration
    counter = 0
    container.register_singleton(:counter) { counter += 1 }

    assert_equal 1, container.resolve(:counter)
    assert_equal 1, container.resolve(:counter) # Should return same instance

    # Test instance registration
    instance = Object.new
    container.register_instance(:instance, instance)
    assert_same instance, container.resolve(:instance)
  end

  test "container raises errors for invalid operations" do
    container = RailsLiveReload::Container.new

    # Test service not found
    assert_raises(RailsLiveReload::Container::ServiceNotFoundError) do
      container.resolve(:nonexistent)
    end

    # Test duplicate registration
    container.register(:duplicate) { "first" }
    assert_raises(RailsLiveReload::Container::ServiceAlreadyRegisteredError) do
      container.register(:duplicate) { "second" }
    end
  end

  test "configuration validation works correctly" do
    config = RailsLiveReload::Config.new
    validator = RailsLiveReload::ConfigValidator.new(config)

    # Valid configuration should pass
    assert validator.valid?

    # Invalid URL should fail
    config.url = "invalid-url"
    assert_not validator.valid?
    assert validator.errors.any? { |error| error.include?("URL must start with /") }
  end

  test "configuration validation catches invalid patterns" do
    config = RailsLiveReload::Config.new
    config.patterns = { "invalid" => :always }

    validator = RailsLiveReload::ConfigValidator.new(config)
    assert_not validator.valid?
    assert validator.errors.any? { |error| error.include?("Pattern must be a Regexp") }
  end

  test "error handler retry mechanism works" do
    attempt_count = 0

    # Test successful retry
    result = RailsLiveReload::ErrorHandler.with_retry(max_attempts: 3) do
      attempt_count += 1
      raise "Temporary error" if attempt_count < 2
      "success"
    end

    assert_equal "success", result
    assert_equal 2, attempt_count
  end

  test "error handler timeout works" do
    assert_raises(RailsLiveReload::ErrorHandler::TimeoutError) do
      RailsLiveReload::ErrorHandler.with_timeout(0.1) do
        sleep(0.2)
      end
    end
  end

  test "error handler safe execution doesn't raise" do
    result = RailsLiveReload::ErrorHandler.safe_execute("test") do
      raise "This should not propagate"
    end

    assert_nil result
  end

  test "checker works with dependency injection" do
    checker = RailsLiveReload::Checker.new

    # Test file updates
    files = { "test.rb" => 123456789 }
    checker.update_files(files)

    assert_equal 1, checker.file_count
    assert checker.has_file?("test.rb")
    assert_equal 123456789, checker.file_mtime("test.rb")
  end

  test "checker scan works correctly" do
    checker = RailsLiveReload::Checker.new

    # Set up test files
    files = {
      "app/views/test.erb" => 123456790,
      "app/assets/test.css" => 123456791,
      "other/file.txt" => 123456792
    }
    checker.update_files(files)

    # Set up patterns
    patterns = {
      %r{app/views/.+\.erb$} => :on_change,
      %r{app/assets/.+\.css$} => :always
    }

    # Test scan with timestamp before all files
    rendered_files = ["app/views/test.erb"]
    result = checker.scan(123456789, rendered_files, patterns)

    # Should include both the rendered view and the CSS file
    assert_includes result, "app/views/test.erb"
    assert_includes result, "app/assets/test.css"
    assert_not_includes result, "other/file.txt"
  end

  test "watcher can be created with dependency injection" do
    config = RailsLiveReload::Config.new
    error_handler = RailsLiveReload::ErrorHandler.new

    watcher = RailsLiveReload::Watcher.new(
      config: config,
      error_handler: error_handler
    )

    assert_equal config, watcher.config
    assert_equal error_handler, watcher.error_handler
    assert_equal config.root_path, watcher.root
  end

  test "server can be created with dependency injection" do
    config = RailsLiveReload::Config.new
    checker = RailsLiveReload::Checker.new
    error_handler = RailsLiveReload::ErrorHandler.new

    server = RailsLiveReload::Server::Base.new(
      config: config,
      checker: checker,
      error_handler: error_handler
    )

    assert_equal config, server.config
    assert_equal checker, server.checker
    assert_equal error_handler, server.error_handler
  end

  test "main module uses dependency injection" do
    # Test that services are properly registered
    container = RailsLiveReload.container

    assert container.registered?(:config)
    assert container.registered?(:checker)
    assert container.registered?(:error_handler)
    assert container.registered?(:watcher)
    assert container.registered?(:server)
  end

  test "main module provides service access" do
    # Test that we can access services through the main module
    # Skip auto-initialization for this test
    RailsLiveReload.instance_variable_set(:@container, nil)

    # Manually create container without auto-start
    container = RailsLiveReload.container
    assert_instance_of RailsLiveReload::Server::Base, RailsLiveReload.server
    assert_instance_of RailsLiveReload::Watcher, RailsLiveReload.watcher
  end

  test "configuration validation is called during configure" do
    # Test that invalid configuration raises an error
    assert_raises(RailsLiveReload::ConfigValidator::ValidationError) do
      RailsLiveReload.configure do |config|
        config.url = "invalid-url"
      end
    end
  end

  test "logger provides structured logging" do
    logger = RailsLiveReload::Logger.new(level: :debug, output: StringIO.new)

    # Test basic logging
    assert_nothing_raised do
      logger.info("Test message", component: "test")
      logger.error("Error message", error_class: "TestError")
      logger.log_watcher_event("test_event", file_count: 5)
    end
  end

  test "logger context works correctly" do
    output = StringIO.new
    logger = RailsLiveReload::Logger.new(level: :debug, output: output)

    logger.with_context(request_id: "123") do
      logger.info("Test message")
    end

    logged_output = output.string
    assert_includes logged_output, "request_id=123"
  end

  test "backward compatibility is maintained" do
    # Test that legacy class methods still work (with deprecation warnings)
    assert_nothing_raised do
      RailsLiveReload::Checker.files = { "test.rb" => 123 }
      files = RailsLiveReload::Checker.files
      assert_equal({ "test.rb" => 123 }, files)
    end
  end
end
