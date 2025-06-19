# frozen_string_literal: true

require "listen"
require "rails_live_reload/version"
require "rails_live_reload/config"
require "rails_live_reload/container"
require "rails_live_reload/watcher"
require "rails_live_reload/server/connections"
require "rails_live_reload/server/base"
require "rails_live_reload/middleware/base"
require "rails_live_reload/instrument/metrics_collector"
require "rails_live_reload/thread/current_request"
require "rails_live_reload/checker"
require "rails_live_reload/command"
require "rails_live_reload/engine"
require "rails_live_reload/error_handler"
require "rails_live_reload/logger"
require "rails_live_reload/hooks"

module RailsLiveReload
  # Internal constants for message types and events
  INTERNAL = {
    message_types: {
      welcome: "welcome",
      disconnect: "disconnect",
      ping: "ping",
    },
    disconnect_reasons: {
      invalid_request: "invalid_request",
      remote: "remote"
    },
    socket_events: {
      reload: 'reload',
      css_reload: 'css_reload'
    },
    protocols: ["rails-live-reload-v1-json"].freeze
  }.freeze

  class << self
    # Service container for dependency injection
    def container
      @container ||= Container.new.tap do |c|
        register_services(c)
      end
    end

    # Get the server instance
    def server
      container.resolve(:server)
    end

    # Get the watcher instance
    def watcher
      container.resolve(:watcher)
    end

    # Get the hooks instance
    def hooks
      container.resolve(:hooks)
    end

    # Convenience method to register a reload hook
    def register_reload_hook(name, priority: 50, &block)
      hooks.register_reload_hook(name, priority: priority, &block)
    end

    # Convenience method to register a custom message handler
    def register_message_handler(message_type, &block)
      hooks.register_message_handler(message_type, &block)
    end

    # Start all services
    def start!
      return unless enabled?

      Logger.info("Starting Rails Live Reload")

      ErrorHandler.safe_execute("service_startup") do
        watcher.start
        server.start
        Logger.info("Rails Live Reload started successfully")
      end
    rescue => error
      Logger.log_error_with_context(error, "Service startup")
      raise
    end

    # Stop all services
    def stop!
      Logger.info("Stopping Rails Live Reload")

      ErrorHandler.graceful_cleanup do
        watcher.stop if container.registered?(:watcher)
        server.stop if container.registered?(:server)
        Logger.info("Rails Live Reload stopped")
      end
    end

    # Reset the container (useful for testing)
    def reset!
      stop! if @container
      @container = nil
    end

    private

    def register_services(container)
      # Register configuration as singleton
      container.register_singleton(:config) { config }

      # Register checker as singleton
      container.register_singleton(:checker) { Checker.new }

      # Register error handler as singleton
      container.register_singleton(:error_handler) { ErrorHandler.new }

      # Register hooks system as singleton
      container.register_singleton(:hooks) { Hooks.new }

      # Register watcher with dependencies
      container.register_singleton(:watcher) do
        Watcher.new(
          config: container.resolve(:config),
          error_handler: container.resolve(:error_handler),
          hooks: container.resolve(:hooks)
        )
      end

      # Register server with dependencies
      container.register_singleton(:server) do
        Server::Base.new(
          config: container.resolve(:config),
          checker: container.resolve(:checker),
          error_handler: container.resolve(:error_handler),
          hooks: container.resolve(:hooks)
        )
      end
    end
  end

  # Legacy compatibility - these methods maintain backward compatibility
  # while using the new dependency injection system internally

  # Deprecated: Use RailsLiveReload.watcher instead
  def self.watcher=(value)
    Logger.warn("Setting watcher directly is deprecated. Use dependency injection instead.")
    container.register_instance(:watcher, value)
  end

  # Initialize services when Rails loads (if enabled)
  def self.initialize!
    return unless enabled?

    # Delay initialization to ensure Rails is fully loaded
    if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
      Rails.application.config.after_initialize do
        RailsLiveReload.start!
      end
    else
      # Fallback for non-Rails environments
      start!
    end
  end
end

# Auto-initialize when the module is loaded
RailsLiveReload.initialize!
