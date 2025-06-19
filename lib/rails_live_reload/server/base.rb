# frozen_string_literal: true

require 'rails_live_reload/web_socket/event_loop'
require 'rails_live_reload/web_socket/message_buffer'
require 'rails_live_reload/web_socket/wrapper'
require 'rails_live_reload/web_socket/client_socket'
require 'rails_live_reload/web_socket/stream'
require 'rails_live_reload/web_socket/base'
require_relative '../error_handler'
require_relative '../logger'

module RailsLiveReload
  module Server
    # This class is based on ActionCable
    # https://github.com/rails/rails/blob/v7.0.3/actioncable/lib/action_cable/server/base.rb
    class Base
      include RailsLiveReload::Server::Connections

      attr_reader :mutex, :config, :error_handler, :checker, :hooks

      def initialize(config:, checker:, error_handler: nil, hooks: nil)
        @config = config
        @checker = checker
        @error_handler = error_handler || ErrorHandler.new
        @hooks = hooks
        @mutex = Monitor.new
        @event_loop = nil
        @socket = nil
        @socket_thread = nil
        @running = false

        Logger.log_server_event("initialized")
      end

      def start
        return if @running
        @running = true
        Logger.log_server_event("starting")
      end

      def stop
        return unless @running
        @running = false
        Logger.log_server_event("stopping")

        ErrorHandler.graceful_cleanup do
          stop_socket_connection
        end
      end

      def reload_all
        @mutex.synchronize do
          active_connections = 0
          failed_connections = []

          connections.each do |connection|
            ErrorHandler.safe_execute("connection_reload") do
              connection.reload
              active_connections += 1
            end || failed_connections << connection
          end

          # Clean up failed connections
          failed_connections.each { |conn| remove_connection(conn) }

          Logger.log_server_event("reload_broadcast_completed",
                                 active_connections: active_connections,
                                 failed_connections: failed_connections.size)
        end
      end

      # Called by Rack to set up the server.
      def call(env)
        start unless @running

        case env["REQUEST_PATH"]
        when config.url
          handle_websocket_request(env)
        when "#{config.url}/script"
          handle_script_request
        else
          handle_not_found
        end
      rescue => error
        Logger.log_error_with_context(error, "Server request handling")
        @error_handler.record_error(error)
        [500, {'Content-Type' => 'text/plain'}, ['Internal Server Error']]
      end

      def client_javascript
        @client_javascript || @mutex.synchronize do
          @client_javascript ||= load_client_javascript
        end
      end

      def event_loop
        @event_loop || @mutex.synchronize do
          @event_loop ||= RailsLiveReload::WebSocket::EventLoop.new
        end
      end

      private

      def handle_websocket_request(env)
        setup_socket_connection
        setup_heartbeat_timer
        request = Rack::Request.new(env)
        RailsLiveReload::WebSocket::Base.new(self, request).process
      end

      def handle_script_request
        content = client_javascript
        return [500, {'Content-Type' => 'text/plain'}, ['Script not available']] unless content

        [200, {
          'Content-Type' => 'application/javascript',
          'Content-Length' => content.size.to_s,
          'Cache-Control' => 'no-store'
        }, [content]]
      end

      def handle_not_found
        if defined?(ActionController::RoutingError)
          raise ActionController::RoutingError, 'Not found'
        else
          [404, {'Content-Type' => 'text/plain'}, ['Not found']]
        end
      end

      def load_client_javascript
        ErrorHandler.with_file_operation do
          script_path = File.join(File.dirname(__FILE__), "../javascript/websocket.js")
          unless File.exist?(script_path)
            Logger.log_server_event("client_script_missing", path: script_path)
            return nil
          end

          File.read(script_path).tap do |content|
            Logger.log_server_event("client_script_loaded", 
                                   path: script_path,
                                   size: content.size)
          end
        end
      rescue => error
        Logger.log_error_with_context(error, "Client JavaScript loading")
        nil
      end

      def setup_socket_connection
        return if @socket && !@socket.closed?

        @socket = ErrorHandler.with_socket_operation(:socket_connect) do
          UNIXSocket.open(config.socket_path)
        end

        start_socket_listener
        Logger.log_server_event("socket_connected", path: config.socket_path.to_s)
      rescue => error
        Logger.log_error_with_context(error, "Socket connection setup")
        @error_handler.record_error(error)

        # Graceful degradation - server can still serve script without socket
        Logger.log_server_event("socket_connection_failed_graceful_degradation")
        nil
      end

      def start_socket_listener
        return unless @socket

        @socket_thread = Thread.new do
          ErrorHandler.safe_execute("socket_listener") do
            loop do
              break unless @running && @socket && !@socket.closed?

              begin
                ErrorHandler.with_timeout(10, "Socket read timeout") do
                  line = @socket.readline
                  handle_socket_message(line)
                end
              rescue EOFError
                Logger.log_server_event("socket_eof_received")
                break
              rescue ErrorHandler::TimeoutError
                Logger.log_server_event("socket_read_timeout")
                # Continue loop, don't break on timeout
              end
            end
          end
        rescue => error
          Logger.log_error_with_context(error, "Socket listener thread")
          @error_handler.record_error(error)

          # Attempt to reconnect after a delay
          sleep(2)
          retry_socket_connection if @running
        end
      end

      def handle_socket_message(line)
        data = ErrorHandler.safe_execute("json_parse") do
          JSON.parse(line)
        end

        return unless data

        case data["event"]
        when RailsLiveReload::INTERNAL[:socket_events][:reload]
          @checker.files = data['files']
          reload_all
          Logger.log_server_event("reload_triggered", file_count: data['files']&.size)
        when RailsLiveReload::INTERNAL[:socket_events][:css_reload]
          @checker.files = data['files']
          reload_all
          Logger.log_server_event("css_reload_triggered", file_count: data['files']&.size)
        else
          Logger.log_server_event("unknown_socket_event", event: data["event"])
        end
      end

      def retry_socket_connection
        return unless @running

        Logger.log_server_event("attempting_socket_reconnection")

        ErrorHandler.with_retry(max_attempts: 3, base_delay: 1.0) do
          stop_socket_connection
          setup_socket_connection
        end
      rescue ErrorHandler::RetryExhaustedError => error
        Logger.log_error_with_context(error, "Socket reconnection")
        @error_handler.record_error(error)
      end

      def stop_socket_connection
        if @socket_thread
          ErrorHandler.graceful_cleanup do
            @socket_thread.join(5) # Wait up to 5 seconds
          end
          @socket_thread = nil
        end

        if @socket
          ErrorHandler.graceful_cleanup do
            @socket.close unless @socket.closed?
          end
          @socket = nil
        end

        Logger.log_server_event("socket_disconnected")
      end
    end
  end
end
