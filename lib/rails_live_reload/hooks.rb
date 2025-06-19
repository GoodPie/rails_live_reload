# frozen_string_literal: true

module RailsLiveReload
  # Hooks system for custom reload logic and WebSocket message handling
  class Hooks
    class << self
      # Get the global hooks instance
      def instance
        @instance ||= new
      end

      # Delegate methods to the instance
      [:register_reload_hook, :register_message_handler, :execute_reload_hooks, 
       :handle_custom_message, :clear_hooks, :reload_hooks, :message_handlers].each do |method|
        define_method(method) do |*args, **kwargs, &block|
          instance.send(method, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      @reload_hooks = {}
      @message_handlers = {}
      @mutex = Mutex.new
    end

    # Register a custom reload hook
    # @param name [Symbol] Unique name for the hook
    # @param priority [Integer] Execution priority (lower numbers execute first)
    # @param block [Proc] The hook logic to execute
    def register_reload_hook(name, priority: 50, &block)
      @mutex.synchronize do
        @reload_hooks[name] = {
          priority: priority,
          handler: block
        }
        Logger.log_config_event("reload_hook_registered", name: name, priority: priority)
      end
    end

    # Register a custom WebSocket message handler
    # @param message_type [String] The message type to handle
    # @param block [Proc] The handler logic
    def register_message_handler(message_type, &block)
      @mutex.synchronize do
        @message_handlers[message_type] = block
        Logger.log_config_event("message_handler_registered", message_type: message_type)
      end
    end

    # Execute all registered reload hooks
    # @param context [Hash] Context information (changed_files, reload_type, etc.)
    # @return [Hash] Results from all hooks
    def execute_reload_hooks(context = {})
      results = {}
      
      @mutex.synchronize do
        sorted_hooks = @reload_hooks.sort_by { |_, config| config[:priority] }
        
        sorted_hooks.each do |name, config|
          ErrorHandler.safe_execute("reload_hook_#{name}") do
            start_time = Time.current
            result = config[:handler].call(context)
            duration = Time.current - start_time
            
            results[name] = result
            Logger.log_performance("reload_hook_#{name}", duration, result: result)
          end
        end
      end

      Logger.log_config_event("reload_hooks_executed", 
                             hook_count: results.size,
                             context: context.keys)
      results
    end

    # Handle a custom WebSocket message
    # @param message_type [String] The message type
    # @param payload [Hash] The message payload
    # @param connection [Object] The WebSocket connection
    # @return [Boolean] True if handled, false if no handler found
    def handle_custom_message(message_type, payload, connection)
      handler = @mutex.synchronize { @message_handlers[message_type] }
      
      return false unless handler

      ErrorHandler.safe_execute("message_handler_#{message_type}") do
        start_time = Time.current
        result = handler.call(payload, connection)
        duration = Time.current - start_time
        
        Logger.log_performance("message_handler_#{message_type}", duration, 
                              payload_keys: payload.keys)
        Logger.log_config_event("custom_message_handled", 
                               message_type: message_type,
                               connection_id: connection.object_id)
        true
      end || false
    end

    # Clear all hooks (useful for testing)
    def clear_hooks
      @mutex.synchronize do
        @reload_hooks.clear
        @message_handlers.clear
        Logger.log_config_event("hooks_cleared")
      end
    end

    # Get all registered reload hooks
    def reload_hooks
      @mutex.synchronize { @reload_hooks.dup }
    end

    # Get all registered message handlers
    def message_handlers
      @mutex.synchronize { @message_handlers.keys }
    end

    # Check if a message type has a handler
    def has_message_handler?(message_type)
      @mutex.synchronize { @message_handlers.key?(message_type) }
    end

    # Get hook statistics
    def statistics
      @mutex.synchronize do
        {
          reload_hooks_count: @reload_hooks.size,
          message_handlers_count: @message_handlers.size,
          reload_hook_names: @reload_hooks.keys,
          message_types: @message_handlers.keys
        }
      end
    end
  end
end