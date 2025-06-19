# frozen_string_literal: true

module RailsLiveReload
  # Configuration validator with meaningful error messages
  class ConfigValidator
    class ValidationError < StandardError; end

    # Socket path length limit on Unix systems
    SOCKET_PATH_MAX_LENGTH = 104

    # Valid reload strategies
    VALID_RELOAD_STRATEGIES = [:on_change, :always].freeze

    def initialize(config)
      @config = config
      @errors = []
    end

    def validate!
      validate_url
      validate_patterns
      validate_ignore_patterns
      validate_socket_path
      validate_root_path
      validate_enabled

      raise ValidationError, format_errors if @errors.any?
    end

    def valid?
      validate!
      true
    rescue ValidationError
      false
    end

    def errors
      @errors.dup
    end

    private

    def validate_url
      return add_error("URL cannot be nil") if @config.url.nil?
      return add_error("URL cannot be empty") if @config.url.empty?
      return add_error("URL must start with /") unless @config.url.start_with?("/")
      
      # Check for valid URL characters
      unless @config.url.match?(/\A\/[\w\-\/]*\z/)
        add_error("URL contains invalid characters. Only alphanumeric, hyphens, and slashes allowed")
      end
    end

    def validate_patterns
      return add_error("Patterns cannot be nil") if @config.patterns.nil?
      return add_error("Patterns must be a Hash") unless @config.patterns.is_a?(Hash)
      return add_error("At least one pattern must be configured") if @config.patterns.empty?

      @config.patterns.each do |pattern, strategy|
        validate_pattern(pattern, strategy)
      end
    end

    def validate_pattern(pattern, strategy)
      unless pattern.is_a?(Regexp)
        add_error("Pattern must be a Regexp, got #{pattern.class}")
        return
      end

      unless VALID_RELOAD_STRATEGIES.include?(strategy)
        add_error("Invalid reload strategy '#{strategy}'. Must be one of: #{VALID_RELOAD_STRATEGIES.join(', ')}")
      end

      # Test if pattern is valid by trying to match against a test string
      begin
        pattern.match?("test")
      rescue RegexpError => e
        add_error("Invalid regex pattern: #{e.message}")
      end
    end

    def validate_ignore_patterns
      return add_error("Ignore patterns cannot be nil") if @config.ignore_patterns.nil?
      return add_error("Ignore patterns must be an Array") unless @config.ignore_patterns.is_a?(Array)

      @config.ignore_patterns.each_with_index do |pattern, index|
        unless pattern.is_a?(Regexp)
          add_error("Ignore pattern at index #{index} must be a Regexp, got #{pattern.class}")
          next
        end

        begin
          pattern.match?("test")
        rescue RegexpError => e
          add_error("Invalid ignore regex pattern at index #{index}: #{e.message}")
        end
      end
    end

    def validate_socket_path
      begin
        socket_path = @config.socket_path
        return add_error("Socket path cannot be nil") if socket_path.nil?

        socket_path_str = socket_path.to_s
        return add_error("Socket path cannot be empty") if socket_path_str.empty?

        if socket_path_str.length > SOCKET_PATH_MAX_LENGTH
          add_error("Socket path too long (#{socket_path_str.length} chars). Maximum allowed: #{SOCKET_PATH_MAX_LENGTH}")
        end

        # Check if directory is writable
        socket_dir = File.dirname(socket_path_str)
        unless File.exist?(socket_dir)
          begin
            FileUtils.mkdir_p(socket_dir)
          rescue => e
            add_error("Cannot create socket directory #{socket_dir}: #{e.message}")
            return
          end
        end

        unless File.writable?(socket_dir)
          add_error("Socket directory #{socket_dir} is not writable")
        end
      rescue => e
        add_error("Error validating socket path: #{e.message}")
      end
    end

    def validate_root_path
      begin
        root_path = @config.root_path
        return add_error("Root path cannot be nil") if root_path.nil?

        root_path_str = root_path.to_s
        return add_error("Root path cannot be empty") if root_path_str.empty?
        return add_error("Root path does not exist: #{root_path_str}") unless File.exist?(root_path_str)
        return add_error("Root path is not a directory: #{root_path_str}") unless File.directory?(root_path_str)
        return add_error("Root path is not readable: #{root_path_str}") unless File.readable?(root_path_str)
      rescue => e
        add_error("Error validating root path: #{e.message}")
      end
    end

    def validate_enabled
      unless [true, false].include?(@config.enabled)
        add_error("Enabled must be true or false, got #{@config.enabled.class}")
      end
    end

    def add_error(message)
      @errors << message
    end

    def format_errors
      "Configuration validation failed:\n" + @errors.map { |error| "  - #{error}" }.join("\n")
    end
  end
end