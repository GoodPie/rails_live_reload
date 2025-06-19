# frozen_string_literal: true

require 'timeout'

module RailsLiveReload
  # Error handling utilities with retry mechanisms and timeout handling
  class ErrorHandler
    class RetryExhaustedError < StandardError; end
    class TimeoutError < StandardError; end

    # Default retry configuration
    DEFAULT_RETRY_CONFIG = {
      max_attempts: 3,
      base_delay: 0.5,
      max_delay: 30.0,
      backoff_factor: 2.0,
      jitter: true
    }.freeze

    # Default timeout configuration
    DEFAULT_TIMEOUT_CONFIG = {
      socket_connect: 5.0,
      socket_read: 10.0,
      socket_write: 5.0,
      file_operation: 30.0
    }.freeze

    class << self
      # Execute block with retry logic and exponential backoff
      def with_retry(config = {}, &block)
        config = DEFAULT_RETRY_CONFIG.merge(config)
        attempt = 1
        last_error = nil

        while attempt <= config[:max_attempts]
          begin
            return block.call
          rescue => error
            last_error = error
            
            if attempt == config[:max_attempts]
              raise RetryExhaustedError, "Failed after #{config[:max_attempts]} attempts. Last error: #{error.message}"
            end

            delay = calculate_delay(attempt, config)
            Rails.logger&.warn("Attempt #{attempt} failed: #{error.message}. Retrying in #{delay}s...")
            
            sleep(delay)
            attempt += 1
          end
        end
      end

      # Execute block with timeout
      def with_timeout(seconds, error_message = nil, &block)
        Timeout.timeout(seconds, TimeoutError, error_message || "Operation timed out after #{seconds}s") do
          block.call
        end
      rescue Timeout::Error => e
        raise TimeoutError, e.message
      end

      # Execute socket operation with proper error handling
      def with_socket_operation(operation_type, &block)
        timeout = DEFAULT_TIMEOUT_CONFIG[operation_type] || DEFAULT_TIMEOUT_CONFIG[:socket_connect]
        
        with_timeout(timeout, "Socket #{operation_type} timed out after #{timeout}s") do
          with_retry(max_attempts: 2, base_delay: 0.1) do
            block.call
          end
        end
      rescue => error
        Rails.logger&.error("Socket #{operation_type} failed: #{error.message}")
        raise
      end

      # Execute file system operation with proper error handling
      def with_file_operation(&block)
        timeout = DEFAULT_TIMEOUT_CONFIG[:file_operation]
        
        with_timeout(timeout, "File operation timed out after #{timeout}s") do
          with_retry(max_attempts: 3, base_delay: 0.2) do
            block.call
          end
        end
      rescue => error
        Rails.logger&.error("File operation failed: #{error.message}")
        raise
      end

      # Safe execution that logs errors but doesn't raise
      def safe_execute(context = "operation", &block)
        block.call
      rescue => error
        Rails.logger&.error("Safe execution failed in #{context}: #{error.message}")
        Rails.logger&.debug(error.backtrace.join("\n")) if Rails.logger&.debug?
        nil
      end

      # Graceful cleanup with error handling
      def graceful_cleanup(&block)
        block.call
      rescue => error
        Rails.logger&.warn("Cleanup failed: #{error.message}")
        # Don't re-raise cleanup errors
      end

      private

      def calculate_delay(attempt, config)
        base_delay = config[:base_delay]
        backoff_factor = config[:backoff_factor]
        max_delay = config[:max_delay]
        jitter = config[:jitter]

        # Exponential backoff: base_delay * (backoff_factor ^ (attempt - 1))
        delay = base_delay * (backoff_factor ** (attempt - 1))
        delay = [delay, max_delay].min

        # Add jitter to prevent thundering herd
        if jitter
          jitter_amount = delay * 0.1 * rand
          delay += jitter_amount
        end

        delay
      end
    end

    # Instance methods for stateful error handling
    def initialize(config = {})
      @retry_config = DEFAULT_RETRY_CONFIG.merge(config[:retry] || {})
      @timeout_config = DEFAULT_TIMEOUT_CONFIG.merge(config[:timeout] || {})
      @error_count = 0
      @last_error_time = nil
    end

    def with_retry(&block)
      self.class.with_retry(@retry_config, &block)
    end

    def with_timeout(operation_type, &block)
      timeout = @timeout_config[operation_type] || @timeout_config[:socket_connect]
      self.class.with_timeout(timeout, &block)
    end

    def record_error(error)
      @error_count += 1
      @last_error_time = Time.current
      Rails.logger&.error("Error recorded: #{error.message} (total errors: #{@error_count})")
    end

    def error_rate_exceeded?(threshold = 10, window_seconds = 60)
      return false unless @last_error_time
      
      time_since_last_error = Time.current - @last_error_time
      time_since_last_error < window_seconds && @error_count > threshold
    end

    def reset_error_count
      @error_count = 0
      @last_error_time = nil
    end

    attr_reader :error_count, :last_error_time
  end
end