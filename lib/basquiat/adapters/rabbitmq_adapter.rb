require 'bunny'

module Basquiat
  module Adapters
    # The RabbitMQ adapter for Basquiat
    class RabbitMq
      include Basquiat::Adapters::Base

      def default_options
        { failover:  { default_timeout: 5, max_retries: 5 },
          servers:   [{ host: 'localhost', port: 5672 }],
          queue:     { name: Basquiat.configuration.queue_name, options: { durable: true } },
          exchange:  { name: Basquiat.configuration.exchange_name, options: { durable: true } },
          publisher: { confirm: true },
          auth:      { user: 'guest', password: 'guest' } }
      end

      def subscribe_to(event_name, proc)
        procs[event_name] = proc
      end

      # TODO: Channel Level Errors
      def publish(event, message, keep_open: false)
        channel.confirm_select if options[:publisher][:confirm]
        exchange.publish(Basquiat::Adapters::Base.json_encode(message), routing_key: event)
        disconnect unless keep_open
      rescue Bunny::ConnectionForced, Bunny::NetworkFailure
        handle_network_failures
      end

      # TODO: Manual ACK and Requeue
      def listen(block: true)
        procs.keys.each { |key| bind_queue(key) }
        queue.subscribe(block: block) do |di, _, msg|
          message = Basquiat::Adapters::Base.json_decode(msg)
          procs[di.routing_key].call(message)
        end
      rescue Bunny::ConnectionForced, Bunny::NetworkFailure, StandardError => error
        handle_network_failures
        warn "Retrying the listener => #{error.class}"
        retry
      end

      def connect
        connection.start
        current_server[:retries] = 0
      rescue Bunny::ConnectionForced, Bunny::TCPConnectionFailed => error
        if current_server.fetch(:retries, 0) <= failover_opts[:max_retries]
          handle_network_failures
          retry
        else
          raise(error)
        end
      end

      def connection_uri
        current_server_uri
      end

      private

      def failover_opts
        options[:failover]
      end

      def bind_queue(event_name)
        queue.bind(exchange, routing_key: event_name)
      end

      def reset_connection
        @connection, @channel, @exchange, @queue = nil, nil, nil, nil
      end

      def disconnect
        connection.close_all_channels
        connection.close
        reset_connection
      end

      def rotate_servers
        return unless options[:servers].any? { |server| server.fetch(:retries, 0) < failover_opts[:max_retries] }
        options[:servers].rotate!
      end

      def handle_network_failures
        warn "[WARN] Handling connection to #{current_server_uri}"
        retries = current_server.fetch(:retries, 0)
        current_server[:retries] = retries + 1
        if retries < failover_opts[:max_retries]
          warn("[WARN]: Connection failed retrying in #{failover_opts[:default_timeout]} seconds")
          sleep(failover_opts[:default_timeout])
        else
          rotate_servers
        end
        reset_connection
      end

      def connection
        @connection ||= Bunny.new(current_server_uri)
      end

      def channel
        connect
        @channel ||= connection.create_channel
      end

      def queue
        @queue ||= channel.queue(options[:queue][:name], options[:queue][:options])
      end

      def exchange
        @exchange ||= channel.topic(options[:exchange][:name], options[:exchange][:options])
      end

      def current_server
        options[:servers].first
      end

      def current_server_uri
        auth = current_server[:auth] || options[:auth]
        "amqp://#{auth[:user]}:#{auth[:password]}@#{current_server[:host]}:#{current_server[:port]}"
      end
    end
  end
end
