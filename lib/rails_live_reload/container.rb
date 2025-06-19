# frozen_string_literal: true

module RailsLiveReload
  # Service container for dependency injection
  # Replaces global state management with proper service registration and resolution
  class Container
    class ServiceNotFoundError < StandardError; end
    class ServiceAlreadyRegisteredError < StandardError; end

    def initialize
      @services = {}
      @instances = {}
      @mutex = Mutex.new
    end

    # Register a service with a factory block
    def register(name, &factory)
      @mutex.synchronize do
        raise ServiceAlreadyRegisteredError, "Service #{name} is already registered" if @services.key?(name)
        @services[name] = factory
      end
    end

    # Register a singleton service
    def register_singleton(name, &factory)
      @mutex.synchronize do
        raise ServiceAlreadyRegisteredError, "Service #{name} is already registered" if @services.key?(name)
        @services[name] = -> { @instances[name] ||= factory.call }
      end
    end

    # Register an instance directly
    def register_instance(name, instance)
      @mutex.synchronize do
        @instances[name] = instance
        @services[name] = -> { instance }
      end
    end

    # Resolve a service
    def resolve(name)
      factory = @services[name]
      raise ServiceNotFoundError, "Service #{name} not found" unless factory
      factory.call
    end

    # Check if service is registered
    def registered?(name)
      @services.key?(name)
    end

    # Clear all services (useful for testing)
    def clear
      @mutex.synchronize do
        @services.clear
        @instances.clear
      end
    end

    # Get all registered service names
    def service_names
      @services.keys
    end
  end
end
