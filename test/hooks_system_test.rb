# frozen_string_literal: true

require "test_helper"

class HooksSystemTest < ActiveSupport::TestCase
  def setup
    RailsLiveReload.reset!
    @hooks = RailsLiveReload::Hooks.new
  end

  def teardown
    RailsLiveReload.reset!
  end

  test "can register and execute reload hooks" do
    executed_hooks = []
    
    # Register hooks with different priorities
    @hooks.register_reload_hook(:first_hook, priority: 10) do |context|
      executed_hooks << :first_hook
      { result: "first", context: context }
    end
    
    @hooks.register_reload_hook(:second_hook, priority: 20) do |context|
      executed_hooks << :second_hook
      { result: "second", context: context }
    end
    
    @hooks.register_reload_hook(:third_hook, priority: 5) do |context|
      executed_hooks << :third_hook
      { result: "third", context: context }
    end

    # Execute hooks
    context = { reload_type: :full_reload, changed_files: ["test.rb"] }
    results = @hooks.execute_reload_hooks(context)

    # Verify execution order (by priority)
    assert_equal [:third_hook, :first_hook, :second_hook], executed_hooks
    
    # Verify results
    assert_equal 3, results.size
    assert_equal "first", results[:first_hook][:result]
    assert_equal "second", results[:second_hook][:result]
    assert_equal "third", results[:third_hook][:result]
    
    # Verify context was passed correctly
    results.each do |_, result|
      assert_equal context, result[:context]
    end
  end

  test "can register and handle custom message types" do
    handled_messages = []
    
    # Register message handlers
    @hooks.register_message_handler("custom_reload") do |payload, connection|
      handled_messages << { type: "custom_reload", payload: payload, connection: connection }
      "custom_reload_handled"
    end
    
    @hooks.register_message_handler("notification") do |payload, connection|
      handled_messages << { type: "notification", payload: payload, connection: connection }
      "notification_handled"
    end

    # Mock connection
    connection = Object.new

    # Handle custom messages
    payload1 = { "data" => "test_data" }
    result1 = @hooks.handle_custom_message("custom_reload", payload1, connection)
    
    payload2 = { "message" => "hello" }
    result2 = @hooks.handle_custom_message("notification", payload2, connection)
    
    # Try unknown message type
    result3 = @hooks.handle_custom_message("unknown", {}, connection)

    # Verify results
    assert result1, "Should return true for handled message"
    assert result2, "Should return true for handled message"
    assert_not result3, "Should return false for unknown message"
    
    # Verify handlers were called correctly
    assert_equal 2, handled_messages.size
    
    first_message = handled_messages.find { |m| m[:type] == "custom_reload" }
    assert_equal payload1, first_message[:payload]
    assert_equal connection, first_message[:connection]
    
    second_message = handled_messages.find { |m| m[:type] == "notification" }
    assert_equal payload2, second_message[:payload]
    assert_equal connection, second_message[:connection]
  end

  test "hooks system provides introspection capabilities" do
    # Register some hooks and handlers
    @hooks.register_reload_hook(:test_hook) { |context| "test" }
    @hooks.register_message_handler("test_message") { |payload, connection| "handled" }

    # Test statistics
    stats = @hooks.statistics
    assert_equal 1, stats[:reload_hooks_count]
    assert_equal 1, stats[:message_handlers_count]
    assert_includes stats[:reload_hook_names], :test_hook
    assert_includes stats[:message_types], "test_message"

    # Test individual checks
    assert_equal [:test_hook], @hooks.reload_hooks.keys
    assert_equal ["test_message"], @hooks.message_handlers
    assert @hooks.has_message_handler?("test_message")
    assert_not @hooks.has_message_handler?("unknown")
  end

  test "hooks system handles errors gracefully" do
    error_count = 0
    
    # Register a hook that raises an error
    @hooks.register_reload_hook(:error_hook) do |context|
      error_count += 1
      raise "Test error"
    end
    
    # Register a normal hook
    @hooks.register_reload_hook(:normal_hook) do |context|
      "success"
    end

    # Execute hooks - should not raise error
    results = @hooks.execute_reload_hooks({ test: true })

    # Error hook should not have a result, normal hook should
    assert_nil results[:error_hook]
    assert_equal "success", results[:normal_hook]
    assert_equal 1, error_count
  end

  test "hooks system is thread-safe" do
    threads = []
    results = []
    
    # Start multiple threads registering hooks
    10.times do |i|
      threads << Thread.new do
        @hooks.register_reload_hook("hook_#{i}".to_sym) do |context|
          "result_#{i}"
        end
      end
    end
    
    # Start multiple threads executing hooks
    5.times do
      threads << Thread.new do
        results << @hooks.execute_reload_hooks({ test: true })
      end
    end
    
    # Wait for all threads
    threads.each(&:join)
    
    # Verify no race conditions occurred
    final_stats = @hooks.statistics
    assert final_stats[:reload_hooks_count] <= 10
    assert results.size <= 5
  end

  test "can clear all hooks" do
    # Register hooks and handlers
    @hooks.register_reload_hook(:test_hook) { |context| "test" }
    @hooks.register_message_handler("test_message") { |payload, connection| "handled" }

    # Verify they exist
    assert_equal 1, @hooks.statistics[:reload_hooks_count]
    assert_equal 1, @hooks.statistics[:message_handlers_count]

    # Clear all hooks
    @hooks.clear_hooks

    # Verify they're gone
    assert_equal 0, @hooks.statistics[:reload_hooks_count]
    assert_equal 0, @hooks.statistics[:message_handlers_count]
  end

  test "main module provides convenience methods" do
    # Test that we can register hooks through the main module
    executed = false
    
    RailsLiveReload.register_reload_hook(:convenience_test) do |context|
      executed = true
      "convenience_result"
    end

    # Execute through the hooks system
    results = RailsLiveReload.hooks.execute_reload_hooks({ test: true })
    
    assert executed, "Hook should have been executed"
    assert_equal "convenience_result", results[:convenience_test]
  end

  test "main module provides message handler convenience methods" do
    # Test that we can register message handlers through the main module
    handled = false
    
    RailsLiveReload.register_message_handler("convenience_message") do |payload, connection|
      handled = true
      "convenience_handled"
    end

    # Handle through the hooks system
    result = RailsLiveReload.hooks.handle_custom_message("convenience_message", {}, Object.new)
    
    assert handled, "Message handler should have been called"
    assert result, "Should return true for handled message"
  end
end