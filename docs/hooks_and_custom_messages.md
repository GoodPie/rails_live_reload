# Rails Live Reload - Hooks System and Custom WebSocket Messages

This document explains how to use the advanced extensibility features of Rails Live Reload: the hooks system for custom reload logic and support for custom WebSocket message types.

## Table of Contents

- [Hooks System Overview](#hooks-system-overview)
- [Custom Reload Hooks](#custom-reload-hooks)
- [Custom WebSocket Message Types](#custom-websocket-message-types)
- [Examples](#examples)
- [Best Practices](#best-practices)
- [API Reference](#api-reference)

## Hooks System Overview

The hooks system allows you to extend Rails Live Reload with custom logic that executes during reload events and handle custom WebSocket message types. This enables powerful integrations with other tools and custom workflows.

### Key Features

- **Reload Hooks**: Execute custom logic before/during/after reload events
- **Custom Message Types**: Handle custom WebSocket messages from the client
- **Priority-based Execution**: Control the order of hook execution
- **Error Handling**: Graceful error handling that doesn't break the reload process
- **Thread Safety**: All operations are thread-safe

## Custom Reload Hooks

Reload hooks allow you to execute custom logic whenever a reload event occurs. This is useful for:

- Clearing caches
- Notifying external services
- Running custom build processes
- Logging and analytics
- Integration with other development tools

### Basic Usage

```ruby
# config/initializers/rails_live_reload.rb
RailsLiveReload.configure do |config|
  # Your existing configuration...
end

# Register a reload hook
RailsLiveReload.register_reload_hook(:cache_cleaner) do |context|
  # Clear application caches when files change
  Rails.cache.clear if context[:reload_type] == :full_reload
  
  # Log the reload event
  Rails.logger.info "Reload triggered: #{context[:reload_type]} for #{context[:changed_files].size} files"
  
  # Return value is optional but can be useful for debugging
  { cache_cleared: true, timestamp: Time.current }
end
```

### Hook Context

Each hook receives a context hash with the following information:

```ruby
{
  reload_type: :full_reload,  # or :css_reload
  changed_files: ["app/views/users/index.html.erb", "app/assets/stylesheets/application.css"],
  files: { "file1.rb" => 1234567890, "file2.css" => 1234567891 }  # All tracked files with timestamps
}
```

### Priority-based Execution

You can control the order of hook execution using priorities (lower numbers execute first):

```ruby
# This hook runs first (priority 10)
RailsLiveReload.register_reload_hook(:pre_reload_setup, priority: 10) do |context|
  puts "Setting up before reload..."
end

# This hook runs second (priority 50, which is the default)
RailsLiveReload.register_reload_hook(:main_reload_logic) do |context|
  puts "Main reload logic..."
end

# This hook runs last (priority 90)
RailsLiveReload.register_reload_hook(:post_reload_cleanup, priority: 90) do |context|
  puts "Cleaning up after reload..."
end
```

### Advanced Hook Examples

#### Cache Management Hook

```ruby
RailsLiveReload.register_reload_hook(:smart_cache_management, priority: 20) do |context|
  case context[:reload_type]
  when :css_reload
    # Only clear view-related caches for CSS changes
    ActionView::LookupContext::DetailsKey.clear
  when :full_reload
    # Clear all caches for full reloads
    Rails.cache.clear
    ActionView::LookupContext::DetailsKey.clear
  end
  
  { cache_strategy: context[:reload_type], cleared_at: Time.current }
end
```

#### External Service Notification Hook

```ruby
RailsLiveReload.register_reload_hook(:notify_external_service, priority: 80) do |context|
  # Notify external development tools about the reload
  begin
    Net::HTTP.post_form(
      URI('http://localhost:3001/reload-notification'),
      {
        reload_type: context[:reload_type],
        changed_files: context[:changed_files].to_json,
        timestamp: Time.current.iso8601
      }
    )
    { notification_sent: true }
  rescue => e
    Rails.logger.warn "Failed to notify external service: #{e.message}"
    { notification_sent: false, error: e.message }
  end
end
```

#### Custom Build Process Hook

```ruby
RailsLiveReload.register_reload_hook(:custom_build_process, priority: 30) do |context|
  # Run custom build process for specific file types
  js_files = context[:changed_files].select { |file| file.end_with?('.js', '.ts') }
  
  if js_files.any?
    system('npm run build:dev')
    { build_triggered: true, processed_files: js_files }
  else
    { build_triggered: false }
  end
end
```

## Custom WebSocket Message Types

Custom WebSocket message types allow you to handle messages sent from the client-side JavaScript to the Rails Live Reload server. This enables bidirectional communication for advanced features.

### Basic Usage

```ruby
# Register a custom message handler
RailsLiveReload.register_message_handler("custom_notification") do |payload, connection|
  # Handle the custom message
  Rails.logger.info "Received custom notification: #{payload['message']}"
  
  # You can access the WebSocket connection if needed
  # connection.transmit({ type: "response", message: "Notification received" })
  
  # Return value indicates successful handling
  "notification_processed"
end
```

### Client-Side Integration

To send custom messages from the client, you'll need to extend the JavaScript client:

```javascript
// In your application's JavaScript
document.addEventListener('DOMContentLoaded', function() {
  // Wait for Rails Live Reload to initialize
  setTimeout(function() {
    const railsLiveReload = window.RailsLiveReload?.instance;
    
    if (railsLiveReload && railsLiveReload.connection) {
      // Send a custom message
      railsLiveReload.connection.send(JSON.stringify({
        event: "custom_notification",
        message: "Hello from the client!",
        timestamp: Date.now()
      }));
    }
  }, 1000);
});
```

### Advanced Message Handler Examples

#### Analytics Event Handler

```ruby
RailsLiveReload.register_message_handler("analytics_event") do |payload, connection|
  # Log analytics events from the client
  event_data = {
    action: payload['action'],
    url: payload['url'],
    timestamp: Time.current,
    user_agent: payload['user_agent']
  }
  
  # Store in database or send to analytics service
  AnalyticsEvent.create(event_data) if defined?(AnalyticsEvent)
  
  Rails.logger.info "Analytics event recorded: #{event_data}"
  "analytics_recorded"
end
```

#### Development Tool Integration

```ruby
RailsLiveReload.register_message_handler("dev_tool_command") do |payload, connection|
  case payload['command']
  when 'clear_logs'
    # Clear development logs
    File.truncate(Rails.root.join('log/development.log'), 0)
    connection.transmit({ type: "response", message: "Logs cleared" })
    
  when 'restart_server'
    # Trigger server restart (be careful with this!)
    Thread.new { sleep(1); Process.kill('USR2', Process.pid) }
    connection.transmit({ type: "response", message: "Server restart initiated" })
    
  when 'run_tests'
    # Run specific tests
    test_files = payload['test_files'] || []
    result = system("bundle exec rails test #{test_files.join(' ')}")
    connection.transmit({ 
      type: "test_result", 
      success: result,
      files: test_files 
    })
  end
  
  "command_executed"
end
```

## Examples

### Complete Integration Example

Here's a complete example showing how to set up both reload hooks and custom message handlers:

```ruby
# config/initializers/rails_live_reload.rb
RailsLiveReload.configure do |config|
  # Standard configuration
  config.watch %r{app/views/.+\.(erb|haml|slim)$}, reload: :on_change
  config.watch %r{app/assets/.+\.(css|js)$}, reload: :always
end

# Development workflow hooks
RailsLiveReload.register_reload_hook(:development_workflow, priority: 10) do |context|
  start_time = Time.current
  
  case context[:reload_type]
  when :css_reload
    # Fast path for CSS-only changes
    ActionView::LookupContext::DetailsKey.clear
    
  when :full_reload
    # Full reload workflow
    Rails.cache.clear
    
    # Clear any custom caches
    CustomCache.clear if defined?(CustomCache)
    
    # Notify development tools
    system('echo "Rails Live Reload: Full reload triggered" | nc -U /tmp/dev-notifications.sock') rescue nil
  end
  
  duration = Time.current - start_time
  Rails.logger.debug "Development workflow completed in #{duration.round(3)}s"
  
  { 
    workflow_type: context[:reload_type],
    duration: duration,
    changed_files_count: context[:changed_files].size
  }
end

# Custom message handlers for development tools
RailsLiveReload.register_message_handler("dev_command") do |payload, connection|
  case payload['action']
  when 'ping'
    connection.transmit({ type: "pong", timestamp: Time.current.to_i })
    
  when 'status'
    connection.transmit({ 
      type: "status_response",
      rails_env: Rails.env,
      cache_size: Rails.cache.respond_to?(:stats) ? Rails.cache.stats : "unknown",
      uptime: Time.current - Rails.application.config.rails_live_reload_start_time
    })
    
  when 'clear_cache'
    Rails.cache.clear
    connection.transmit({ type: "cache_cleared", timestamp: Time.current.to_i })
  end
  
  "dev_command_handled"
end

# Store start time for uptime calculation
Rails.application.config.rails_live_reload_start_time = Time.current
```

### Testing Your Hooks

You can test your hooks in the Rails console:

```ruby
# Test reload hooks
context = {
  reload_type: :full_reload,
  changed_files: ["app/views/test.erb"],
  files: { "app/views/test.erb" => Time.current.to_i }
}

results = RailsLiveReload.hooks.execute_reload_hooks(context)
puts results

# Test message handlers
payload = { "action" => "ping", "timestamp" => Time.current.to_i }
connection = OpenStruct.new(transmit: ->(msg) { puts "Transmitted: #{msg}" })

result = RailsLiveReload.hooks.handle_custom_message("dev_command", payload, connection)
puts "Handler result: #{result}"
```

## Best Practices

### Hook Design

1. **Keep hooks fast**: Hooks execute during the reload process, so avoid slow operations
2. **Handle errors gracefully**: Use begin/rescue blocks for operations that might fail
3. **Use appropriate priorities**: Order hooks logically (setup → main logic → cleanup)
4. **Return meaningful values**: Return hashes with useful debugging information

### Message Handler Design

1. **Validate input**: Always validate the payload structure
2. **Use meaningful event names**: Choose descriptive names for your message types
3. **Handle unknown commands**: Gracefully handle unexpected message formats
4. **Limit scope**: Don't expose dangerous operations through message handlers

### Performance Considerations

1. **Async operations**: Use background jobs for slow operations
2. **Conditional execution**: Only run hooks when necessary
3. **Caching**: Cache expensive computations when possible
4. **Monitoring**: Log hook execution times for performance monitoring

### Security Considerations

1. **Input validation**: Always validate message payloads
2. **Rate limiting**: Consider implementing rate limiting for message handlers
3. **Scope limitation**: Only expose safe operations through the WebSocket interface
4. **Environment checks**: Ensure hooks only run in development environment

## API Reference

### RailsLiveReload Module Methods

#### `register_reload_hook(name, priority: 50, &block)`

Registers a reload hook.

- `name` (Symbol): Unique identifier for the hook
- `priority` (Integer): Execution priority (lower numbers execute first)
- `block` (Proc): Hook logic that receives a context hash

#### `register_message_handler(message_type, &block)`

Registers a custom WebSocket message handler.

- `message_type` (String): The message type to handle
- `block` (Proc): Handler logic that receives payload and connection

### Hooks Instance Methods

#### `execute_reload_hooks(context)`

Executes all registered reload hooks with the given context.

#### `handle_custom_message(message_type, payload, connection)`

Handles a custom WebSocket message.

#### `statistics`

Returns statistics about registered hooks and handlers.

#### `clear_hooks`

Clears all registered hooks and handlers (useful for testing).

### Context Hash Structure

```ruby
{
  reload_type: Symbol,      # :full_reload or :css_reload
  changed_files: Array,     # Array of changed file paths
  files: Hash              # Hash of all tracked files with timestamps
}
```

### WebSocket Connection Methods

The connection object passed to message handlers supports:

#### `transmit(message)`

Sends a message to the client.

- `message` (Hash): Message to send (will be JSON-encoded)

---

For more information and updates, see the main [README](../README.md) and [project documentation](https://github.com/railsjazz/rails_live_reload).