# frozen_string_literal: true

require "test_helper"

class HooksIntegrationTest < ActiveSupport::TestCase
  def setup
    RailsLiveReload.reset!
  end

  def teardown
    RailsLiveReload.reset!
  end

  test "watcher executes reload hooks during file changes" do
    config = RailsLiveReload::Config.new
    hooks = RailsLiveReload::Hooks.new
    error_handler = RailsLiveReload::ErrorHandler.new
    
    # Track hook executions
    hook_executions = []
    
    # Register reload hooks
    hooks.register_reload_hook(:pre_reload, priority: 10) do |context|
      hook_executions << {
        name: :pre_reload,
        reload_type: context[:reload_type],
        changed_files: context[:changed_files],
        timestamp: Time.current
      }
      "pre_reload_executed"
    end
    
    hooks.register_reload_hook(:post_reload, priority: 90) do |context|
      hook_executions << {
        name: :post_reload,
        reload_type: context[:reload_type],
        changed_files: context[:changed_files],
        timestamp: Time.current
      }
      "post_reload_executed"
    end

    # Create watcher with hooks
    watcher = RailsLiveReload::Watcher.new(
      config: config,
      error_handler: error_handler,
      hooks: hooks
    )

    # Test full reload
    watcher.send(:reload_all, ["app/views/test.erb", "app/controllers/test_controller.rb"])
    
    # Verify hooks were executed
    assert_equal 2, hook_executions.size
    
    # Verify execution order (pre_reload should come first due to lower priority)
    assert_equal :pre_reload, hook_executions[0][:name]
    assert_equal :post_reload, hook_executions[1][:name]
    
    # Verify context was passed correctly
    hook_executions.each do |execution|
      assert_equal :full_reload, execution[:reload_type]
      assert_equal ["app/views/test.erb", "app/controllers/test_controller.rb"], execution[:changed_files]
    end

    # Clear executions and test CSS reload
    hook_executions.clear
    watcher.send(:reload_css, ["app/assets/stylesheets/application.css"])
    
    # Verify hooks were executed for CSS reload
    assert_equal 2, hook_executions.size
    hook_executions.each do |execution|
      assert_equal :css_reload, execution[:reload_type]
      assert_equal ["app/assets/stylesheets/application.css"], execution[:changed_files]
    end
  end

  test "WebSocket handles custom message types through hooks" do
    # Create a mock server with hooks
    config = RailsLiveReload::Config.new
    checker = RailsLiveReload::Checker.new
    error_handler = RailsLiveReload::ErrorHandler.new
    hooks = RailsLiveReload::Hooks.new
    
    server = RailsLiveReload::Server::Base.new(
      config: config,
      checker: checker,
      error_handler: error_handler,
      hooks: hooks
    )

    # Register custom message handlers
    handled_messages = []
    
    hooks.register_message_handler("custom_notification") do |payload, connection|
      handled_messages << {
        type: "custom_notification",
        payload: payload,
        connection_class: connection.class.name
      }
      "notification_processed"
    end
    
    hooks.register_message_handler("analytics_event") do |payload, connection|
      handled_messages << {
        type: "analytics_event",
        payload: payload,
        connection_class: connection.class.name
      }
      "analytics_recorded"
    end

    # Create a mock request and WebSocket connection
    env = {
      "REQUEST_METHOD" => "GET",
      "HTTP_CONNECTION" => "Upgrade",
      "HTTP_UPGRADE" => "websocket",
      "HTTP_SEC_WEBSOCKET_KEY" => "test-key",
      "HTTP_SEC_WEBSOCKET_VERSION" => "13"
    }
    request = Rack::Request.new(env)
    
    websocket_connection = RailsLiveReload::WebSocket::Base.new(server, request)

    # Test handling custom messages
    custom_payload = {
      "event" => "custom_notification",
      "data" => { "message" => "Hello from custom handler!" }
    }
    
    analytics_payload = {
      "event" => "analytics_event", 
      "data" => { "action" => "page_view", "url" => "/test" }
    }

    # Handle the custom messages
    assert_nothing_raised do
      websocket_connection.send(:handle_channel_command, custom_payload)
      websocket_connection.send(:handle_channel_command, analytics_payload)
    end

    # Verify messages were handled
    assert_equal 2, handled_messages.size
    
    notification_message = handled_messages.find { |m| m[:type] == "custom_notification" }
    assert_not_nil notification_message
    assert_equal custom_payload, notification_message[:payload]
    
    analytics_message = handled_messages.find { |m| m[:type] == "analytics_event" }
    assert_not_nil analytics_message
    assert_equal analytics_payload, analytics_message[:payload]
  end

  test "unknown message types raise appropriate errors" do
    # Create a mock server without custom handlers
    config = RailsLiveReload::Config.new
    checker = RailsLiveReload::Checker.new
    error_handler = RailsLiveReload::ErrorHandler.new
    hooks = RailsLiveReload::Hooks.new
    
    server = RailsLiveReload::Server::Base.new(
      config: config,
      checker: checker,
      error_handler: error_handler,
      hooks: hooks
    )

    # Create a mock request and WebSocket connection
    env = {
      "REQUEST_METHOD" => "GET",
      "HTTP_CONNECTION" => "Upgrade",
      "HTTP_UPGRADE" => "websocket",
      "HTTP_SEC_WEBSOCKET_KEY" => "test-key",
      "HTTP_SEC_WEBSOCKET_VERSION" => "13"
    }
    request = Rack::Request.new(env)
    
    websocket_connection = RailsLiveReload::WebSocket::Base.new(server, request)

    # Test unknown message type
    unknown_payload = {
      "event" => "unknown_message_type",
      "data" => { "test" => "data" }
    }

    # Should raise NotImplementedError for unknown message types
    assert_raises(NotImplementedError) do
      websocket_connection.send(:handle_channel_command, unknown_payload)
    end
  end

  test "hooks system integrates with dependency injection container" do
    # Test that hooks are properly registered in the container
    container = RailsLiveReload.container
    
    assert container.registered?(:hooks)
    
    hooks_instance = container.resolve(:hooks)
    assert_instance_of RailsLiveReload::Hooks, hooks_instance
    
    # Test that the same instance is returned (singleton)
    hooks_instance2 = container.resolve(:hooks)
    assert_same hooks_instance, hooks_instance2
  end

  test "main module convenience methods work with integrated system" do
    # Register hooks through main module
    executed_hooks = []
    
    RailsLiveReload.register_reload_hook(:integration_test) do |context|
      executed_hooks << context
      "integration_success"
    end
    
    handled_messages = []
    RailsLiveReload.register_message_handler("integration_message") do |payload, connection|
      handled_messages << { payload: payload, connection: connection }
      "integration_handled"
    end

    # Get watcher and trigger reload (this should execute our hook)
    watcher = RailsLiveReload.watcher
    watcher.send(:reload_all, ["test_file.rb"])
    
    # Verify hook was executed
    assert_equal 1, executed_hooks.size
    assert_equal :full_reload, executed_hooks[0][:reload_type]
    assert_equal ["test_file.rb"], executed_hooks[0][:changed_files]
    
    # Test message handler through hooks system
    hooks = RailsLiveReload.hooks
    result = hooks.handle_custom_message("integration_message", { test: "data" }, Object.new)
    
    assert result, "Message should have been handled"
    assert_equal 1, handled_messages.size
    assert_equal({ test: "data" }, handled_messages[0][:payload])
  end

  test "hooks system works with error handling" do
    # Register a hook that raises an error
    RailsLiveReload.register_reload_hook(:error_hook) do |context|
      raise "Test error in hook"
    end
    
    # Register a normal hook
    executed = false
    RailsLiveReload.register_reload_hook(:normal_hook) do |context|
      executed = true
      "success"
    end

    # Get watcher and trigger reload
    watcher = RailsLiveReload.watcher
    
    # Should not raise error despite error in hook
    assert_nothing_raised do
      watcher.send(:reload_all, ["test_file.rb"])
    end
    
    # Normal hook should still execute
    assert executed, "Normal hook should have executed despite error in other hook"
  end
end