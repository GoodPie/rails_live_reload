# frozen_string_literal: true

module RailsLiveReload
  # Structured logger for Rails Live Reload
  class Logger
    LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3,
      fatal: 4
    }.freeze

    def initialize(level: :info, output: nil)
      @level = LEVELS[level] || LEVELS[:info]
      @output = output || (defined?(Rails) ? Rails.logger : ::Logger.new(STDOUT))
      @context = {}
    end

    def with_context(context = {})
      old_context = @context
      @context = @context.merge(context)
      yield
    ensure
      @context = old_context
    end

    def debug(message, **metadata)
      log(:debug, message, metadata)
    end

    def info(message, **metadata)
      log(:info, message, metadata)
    end

    def warn(message, **metadata)
      log(:warn, message, metadata)
    end

    def error(message, **metadata)
      log(:error, message, metadata)
    end

    def fatal(message, **metadata)
      log(:fatal, message, metadata)
    end

    def log_watcher_event(event, **metadata)
      info("Watcher: #{event}", component: 'watcher', **metadata)
    end

    def log_server_event(event, **metadata)
      info("Server: #{event}", component: 'server', **metadata)
    end

    def log_socket_event(event, **metadata)
      info("Socket: #{event}", component: 'socket', **metadata)
    end

    def log_config_event(event, **metadata)
      info("Config: #{event}", component: 'config', **metadata)
    end

    def log_error_with_context(error, context = "Unknown")
      error("#{context}: #{error.message}", 
            error_class: error.class.name,
            backtrace: error.backtrace&.first(5))
    end

    def log_performance(operation, duration, **metadata)
      info("Performance: #{operation} completed in #{duration.round(3)}s", 
           operation: operation, 
           duration: duration,
           **metadata)
    end

    def log_connection_event(event, connection_id = nil, **metadata)
      info("Connection #{event}", 
           component: 'connection',
           connection_id: connection_id,
           **metadata)
    end

    def log_file_change(files, change_type = 'modified', **metadata)
      info("File #{change_type}: #{files.size} files", 
           component: 'file_watcher',
           change_type: change_type,
           file_count: files.size,
           files: files.first(10), # Log first 10 files to avoid spam
           **metadata)
    end

    private

    def log(level, message, metadata = {})
      return unless should_log?(level)

      formatted_message = format_message(message, metadata)

      case @output
      when ::Logger
        @output.send(level, formatted_message)
      when StringIO
        @output.puts("[#{level.upcase}] #{formatted_message}")
      when defined?(Rails) && Rails.logger
        Rails.logger.send(level, formatted_message)
      else
        puts "[#{level.upcase}] #{formatted_message}"
      end
    end

    def should_log?(level)
      LEVELS[level] >= @level
    end

    def format_message(message, metadata)
      parts = [message]

      # Add context if present
      if @context.any?
        context_str = @context.map { |k, v| "#{k}=#{v}" }.join(' ')
        parts << "[#{context_str}]"
      end

      # Add metadata if present
      if metadata.any?
        metadata_str = metadata.map { |k, v| "#{k}=#{format_value(v)}" }.join(' ')
        parts << "{#{metadata_str}}"
      end

      parts.join(' ')
    end

    def format_value(value)
      case value
      when String
        value.length > 100 ? "#{value[0..97]}..." : value
      when Array
        "[#{value.size} items]"
      when Hash
        "{#{value.size} keys}"
      else
        value.to_s
      end
    end

    class << self
      def instance
        @instance ||= new
      end

      def configure(level: :info, output: nil)
        @instance = new(level: level, output: output)
      end

      # Delegate methods to instance
      [:debug, :info, :warn, :error, :fatal, :with_context,
       :log_watcher_event, :log_server_event, :log_socket_event,
       :log_config_event, :log_error_with_context, :log_performance,
       :log_connection_event, :log_file_change].each do |method|
        define_method(method) do |*args, **kwargs, &block|
          instance.send(method, *args, **kwargs, &block)
        end
      end
    end
  end
end
