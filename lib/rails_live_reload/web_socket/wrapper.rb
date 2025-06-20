require "websocket/driver"

module RailsLiveReload
  module WebSocket
    # This class is basically copied from ActionCable
    # https://github.com/rails/rails/blob/v7.0.3/actioncable/lib/action_cable/connection/web_socket.rb
    class Wrapper
      def transmit(*args, **kwargs, &block)
        websocket&.transmit(*args, **kwargs, &block)
      end

      def close(*args, **kwargs, &block)
        websocket&.close(*args, **kwargs, &block)
      end

      def protocol(*args, **kwargs, &block)
        websocket&.protocol(*args, **kwargs, &block)
      end

      def rack_response(*args, **kwargs, &block)
        websocket&.rack_response(*args, **kwargs, &block)
      end

      def initialize(env, event_target, event_loop, protocols: RailsLiveReload::INTERNAL[:protocols])
        @websocket = ::WebSocket::Driver.websocket?(env) ? ClientSocket.new(env, event_target, event_loop, protocols) : nil
      end

      def possible?
        websocket
      end

      def alive?
        websocket && websocket.alive?
      end

      private

      attr_reader :websocket
    end
  end
end
