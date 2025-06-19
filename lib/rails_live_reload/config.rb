# frozen_string_literal: true

require_relative 'config_validator'
require_relative 'logger'

module RailsLiveReload
  class << self
    def configure
      yield config
      validate_config!
    end

    def config
      @_config ||= Config.new
    end

    def patterns
      config.patterns
    end

    def ignore_patterns
      config.ignore_patterns
    end

    def enabled?
      config.enabled
    end

    private

    def validate_config!
      validator = ConfigValidator.new(config)
      validator.validate!
    rescue ConfigValidator::ValidationError => e
      Logger.log_config_event("validation_failed", error: e.message)
      raise
    end
  end

  class Config
    # Socket path length limit on Unix systems
    SOCKET_PATH_MAX_LENGTH = 104

    attr_reader :patterns, :ignore_patterns
    attr_accessor :url, :watcher, :files, :enabled
    attr_writer :patterns

    def initialize
      @url = "/rails/live/reload"
      @watcher = nil
      @files = {}
      @enabled = safe_rails_env_check

      # These configs work for 95% apps, see README for more info
      @patterns = {
        %r{app/views/.+\.(erb|haml|slim)$} => :on_change,
        %r{(app|vendor)/(assets|javascript)/\w+/(.+\.(css|js|html|png|jpg|ts|jsx)).*} => :always
      }
      @default_patterns_changed = false

      @ignore_patterns = []
    end

    def root_path
      @root_path ||= safe_rails_root_path
    end

    def watch(pattern, reload: :on_change)
      unless @default_patterns_changed
        @default_patterns_changed = true
        @patterns = {}
      end

      patterns[pattern] = reload
    end

    def ignore(pattern)
      @ignore_patterns << pattern
    end

    def socket_path
      @socket_path ||= calculate_socket_path
    end

    private

    def safe_rails_env_check
      return true unless defined?(::Rails)
      ::Rails.env.development?
    rescue => e
      Logger.log_config_event("rails_env_check_failed", error: e.message)
      false
    end

    def safe_rails_root_path
      return Pathname.new(Dir.pwd) unless defined?(::Rails)
      ::Rails.application.root
    rescue => e
      Logger.log_config_event("rails_root_path_failed", error: e.message)
      Pathname.new(Dir.pwd)
    end

    def calculate_socket_path
      base_path = root_path.join('tmp/sockets/rails_live_reload.sock')

      if base_path.to_s.size <= SOCKET_PATH_MAX_LENGTH
        Logger.log_config_event("socket_path_created", path: base_path.to_s)
        return base_path
      end

      # Fallback to /tmp if path is too long
      app_name = safe_app_name
      fallback_path = Pathname.new("/tmp/rails_live_reload_#{app_name}.sock")

      Logger.log_config_event("socket_path_fallback", 
                             original_path: base_path.to_s,
                             fallback_path: fallback_path.to_s,
                             reason: "path_too_long")

      fallback_path
    end

    def safe_app_name
      return "app" unless defined?(::Rails)
      ::Rails.application.class.name.split('::').first.underscore
    rescue => e
      Logger.log_config_event("app_name_detection_failed", error: e.message)
      "app"
    end
  end
end
