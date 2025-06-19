# frozen_string_literal: true

require "fileutils"
require_relative 'error_handler'
require_relative 'logger'

module RailsLiveReload
  class Watcher
    attr_reader :files, :sockets, :config, :error_handler, :hooks

    def initialize(config:, error_handler: nil, hooks: nil)
      @config = config
      @error_handler = error_handler || ErrorHandler.new
      @hooks = hooks
      @files = {}
      @sockets = []
      @listener = nil
      @socket_server = nil
      @running = false
      @mutex = Mutex.new

      Logger.log_watcher_event("initializing", root_path: root.to_s)
      log_patterns
    end

    def start
      return if @running

      @running = true
      Logger.log_watcher_event("starting")

      ErrorHandler.safe_execute("watcher_initialization") do
        build_tree
        create_socket_directory
        start_socket_server
        start_file_listener
      end
    end

    def stop
      return unless @running

      @running = false
      Logger.log_watcher_event("stopping")

      ErrorHandler.graceful_cleanup do
        stop_file_listener
        stop_socket_server
        cleanup_sockets
      end
    end

    def root
      config.root_path
    end

    private

    def log_patterns
      config.patterns.each do |pattern, rule|
        Logger.log_watcher_event("pattern_registered", pattern: pattern.source, rule: rule)
      end
    end

    def start_file_listener
      @listener_thread = Thread.new do
        ErrorHandler.safe_execute("file_listener") do
          @listener = Listen.to(root, ignore: config.ignore_patterns) do |modified, added, removed|
            handle_file_changes(modified, added, removed)
          end
          @listener.start
        end
      end
    end

    def stop_file_listener
      return unless @listener

      ErrorHandler.graceful_cleanup do
        @listener.stop
        @listener_thread&.join(5) # Wait up to 5 seconds
      end

      @listener = nil
      @listener_thread = nil
    end

    def handle_file_changes(modified, added, removed)
      all_changes = modified + added + removed
      return if all_changes.empty?

      Logger.log_file_change(all_changes, 'detected')

      # Update file modification times with error handling
      all_changes.each do |file|
        ErrorHandler.safe_execute("file_mtime_update") do
          @files[file] = File.mtime(file).to_i
        end
      end

      # Determine reload strategy
      css_only = all_changes.all? { |file| css_file?(file) }

      if css_only
        reload_css(all_changes)
      else
        reload_all(all_changes)
      end
    end

    def build_tree
      Logger.log_watcher_event("building_file_tree", root: root.to_s)

      ErrorHandler.with_file_operation do
        file_count = 0
        Dir.glob(File.join(root, '**', '*')).each do |file|
          next unless File.file?(file)

          ErrorHandler.safe_execute("file_mtime_read") do
            @files[file] = File.mtime(file).to_i
            file_count += 1
          end
        end

        Logger.log_watcher_event("file_tree_built", file_count: file_count)
      end
    end

    def reload_all(changed_files = [])
      # Execute reload hooks if available
      if @hooks
        context = {
          reload_type: :full_reload,
          changed_files: changed_files,
          files: @files
        }
        @hooks.execute_reload_hooks(context)
      end

      data = {
        event: RailsLiveReload::INTERNAL[:socket_events][:reload],
        files: @files
      }.to_json

      broadcast_to_sockets(data, "full_reload", changed_files)
    end

    def reload_css(changed_files = [])
      # Execute reload hooks if available
      if @hooks
        context = {
          reload_type: :css_reload,
          changed_files: changed_files,
          files: @files
        }
        @hooks.execute_reload_hooks(context)
      end

      data = {
        event: RailsLiveReload::INTERNAL[:socket_events][:css_reload],
        files: @files
      }.to_json

      broadcast_to_sockets(data, "css_reload", changed_files)
    end

    def broadcast_to_sockets(data, reload_type, changed_files)
      active_sockets = 0
      failed_sockets = []

      @mutex.synchronize do
        @sockets.each do |socket|
          ErrorHandler.safe_execute("socket_broadcast") do
            ErrorHandler.with_socket_operation(:socket_write) do
              socket.puts(data)
              active_sockets += 1
            end
          end || failed_sockets << socket
        end

        # Clean up failed sockets
        failed_sockets.each { |socket| cleanup_socket(socket) }
      end

      Logger.log_watcher_event("broadcast_completed", 
                              reload_type: reload_type,
                              active_sockets: active_sockets,
                              failed_sockets: failed_sockets.size,
                              changed_files: changed_files.size)
    end

    def css_file?(file)
      file.match?(/\.css(\.|$)/)
    end

    def create_socket_directory
      socket_dir = File.dirname(config.socket_path)

      ErrorHandler.with_file_operation do
        FileUtils.mkdir_p(socket_dir)
        Logger.log_watcher_event("socket_directory_created", path: socket_dir)
      end
    end

    def start_socket_server
      @socket_thread = Thread.new do
        ErrorHandler.with_retry(max_attempts: 3) do
          Socket.unix_server_socket(config.socket_path.to_s) do |server_socket|
            @socket_server = server_socket
            Logger.log_socket_event("server_started", path: config.socket_path.to_s)

            loop do
              break unless @running

              ErrorHandler.safe_execute("socket_accept") do
                socket, _ = server_socket.accept
                handle_new_socket(socket)
              end
            end
          end
        end
      rescue ErrorHandler::RetryExhaustedError => e
        Logger.log_error_with_context(e, "Socket server startup")
        @error_handler.record_error(e)
      end
    end

    def handle_new_socket(socket)
      @mutex.synchronize { @sockets << socket }

      Logger.log_socket_event("connection_accepted", 
                             socket_id: socket.object_id,
                             total_connections: @sockets.size)

      # Handle socket lifecycle in separate thread
      Thread.new do
        ErrorHandler.safe_execute("socket_lifecycle") do
          socket.eof # Wait for socket to close
        ensure
          cleanup_socket(socket)
        end
      end
    end

    def cleanup_socket(socket)
      @mutex.synchronize do
        @sockets.delete(socket)
        ErrorHandler.graceful_cleanup do
          socket.close unless socket.closed?
        end
      end

      Logger.log_socket_event("connection_closed", 
                             socket_id: socket.object_id,
                             remaining_connections: @sockets.size)
    end

    def stop_socket_server
      return unless @socket_server

      ErrorHandler.graceful_cleanup do
        @socket_server.close unless @socket_server.closed?
        @socket_thread&.join(5) # Wait up to 5 seconds
      end

      @socket_server = nil
      @socket_thread = nil
      Logger.log_socket_event("server_stopped")
    end

    def cleanup_sockets
      @mutex.synchronize do
        @sockets.dup.each { |socket| cleanup_socket(socket) }
      end
    end
  end
end
