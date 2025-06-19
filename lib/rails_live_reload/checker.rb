# frozen_string_literal: true

require_relative 'logger'
require_relative 'error_handler'

module RailsLiveReload
  class Checker
    attr_accessor :files

    def initialize
      @files = {}
      @mutex = Mutex.new
      Logger.log_config_event("checker_initialized")
    end

    def scan(dt, rendered_files, patterns)
      @mutex.synchronize do
        ErrorHandler.safe_execute("file_scan") do
          changed_files = find_changed_files(dt)
          relevant_files = filter_relevant_files(changed_files, rendered_files, patterns)

          Logger.log_config_event("scan_completed", 
                                 changed_files: changed_files.size,
                                 relevant_files: relevant_files.size,
                                 timestamp: dt)

          relevant_files
        end || []
      end
    end

    def update_files(new_files)
      return unless new_files.is_a?(Hash)

      @mutex.synchronize do
        @files = new_files.dup
        Logger.log_config_event("files_updated", file_count: @files.size)
      end
    end

    def file_count
      @mutex.synchronize { @files.size }
    end

    def has_file?(file_path)
      @mutex.synchronize { @files.key?(file_path) }
    end

    def file_mtime(file_path)
      @mutex.synchronize { @files[file_path] }
    end

    private

    def find_changed_files(dt)
      changed = []

      @files.each do |file, file_dt|
        next unless file_dt && file_dt > dt

        ErrorHandler.safe_execute("file_change_check") do
          changed << file
        end
      end

      changed
    end

    def filter_relevant_files(changed_files, rendered_files, patterns)
      return [] if changed_files.empty? || patterns.empty?

      result = []

      changed_files.each do |file|
        patterns.each do |pattern, rule|
          if file_matches_rule?(file, pattern, rule, rendered_files)
            result << file
            break # Only add file once, even if it matches multiple patterns
          end
        end
      end

      result
    end

    def file_matches_rule?(file, pattern, rule, rendered_files)
      ErrorHandler.safe_execute("pattern_matching") do
        case rule
        when :always
          # Used for CSS, JS, yaml, helpers, etc. - always reload if pattern matches
          file.match?(pattern)
        when :on_change
          # Used for views - only reload if pattern matches AND file was rendered
          file.match?(pattern) && rendered_files.include?(file)
        else
          Logger.warn("Unknown reload rule: #{rule} for pattern: #{pattern}")
          false
        end
      end || false
    end

    # Class methods for backward compatibility
    class << self
      def files
        Logger.warn("Checker.files is deprecated. Use instance methods instead.")
        @legacy_files ||= {}
      end

      def files=(files)
        Logger.warn("Checker.files= is deprecated. Use instance methods instead.")
        @legacy_files = files
      end

      def scan(dt, rendered_files)
        Logger.warn("Checker.scan is deprecated. Use instance methods instead.")

        # Fallback to legacy behavior for backward compatibility
        patterns = RailsLiveReload.patterns rescue {}
        temp = []

        # all changed files
        files.each do |file, fdt|
          temp << file if fdt && fdt > dt
        end

        result = []

        temp.each do |file|
          patterns.each do |pattern, rule|
            rule_1 = file.match(pattern) && rule == :always
            rule_2 = file.match(pattern) && rendered_files.include?(file)

            if rule_1 || rule_2
              result << file
              break
            end
          end
        end

        result
      end
    end
  end
end
