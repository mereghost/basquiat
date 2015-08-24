require 'bunny'
require 'delegate'

module Basquiat
  module Adapters
    # The RabbitMQ adapter for Basquiat
    class RabbitMq < Basquiat::Adapters::Base
      using Basquiat::HashRefinements


      # Avoid superclass mismatch errors
      require 'basquiat/adapters/rabbitmq/events'
      require 'basquiat/adapters/rabbitmq/message'
      require 'basquiat/adapters/rabbitmq/configuration'
      require 'basquiat/adapters/rabbitmq/connection'
      require 'basquiat/adapters/rabbitmq/session'
      require 'basquiat/adapters/rabbitmq/requeue_strategies'

      # Initializes the superclass using a {Events} object as the procs instance variable
      def initialize
        super(procs: Events.new)
      end

      # Since the RabbitMQ configuration options are quite vast and it's interations with the requeue strategies a bit
      # convoluted it uses a {Configuration} object to handle it all
      def base_options
        @configuration ||= Configuration.new
        @configuration.merge_user_options(Basquiat.configuration.adapter_options)
      end

      # Adds the subscription and register the proc to the event.
      # @param event_name [String] routing key to be matched (and bound to) when listening
      # @param proc [#call] callable object to be run when a message with the said routing_key is received
      def subscribe_to(event_name, proc)
        procs[event_name] = proc
      end

      # Publishes the event to the exchange configured.
      # @param event [String] routing key to be used
      # @param persistent [Boolean] should the session disconnect after the publish
      # @param props [Hash] other properties you wish to publish with the message, such as custom headers etc.
      def publish(event, message, persistent: options[:publisher][:persistent], props: {})
        session.publish(event, message, props)
        disconnect unless persistent
      end

      # Binds the queues and start the event lopp.
      # @param block [Boolean] block the thread
      def listen(block: true)
        procs.keys.each { |key| session.bind_queue(key) }
        session.subscribe(block) do |message|
          strategy.run(message) do
            procs[message.routing_key].call(message)
          end
        end
      end

      # Reset the connection to RabbitMQ.
      def reset_connection
        connection.disconnect
        @connection = nil
        @session    = nil
        @strategy   = nil
      end

      alias_method :disconnect, :reset_connection

      # Lazy initializes the requeue strategy configured for the adapter
      # @return [BaseStrategy]
      def strategy
        @strategy ||= @configuration.strategy.new(session)
      end

      # Lazy initializes and return the session
      # @return [Session]
      def session
        @session ||= Session.new(connection.create_channel, @configuration.session_options)
      end

      private

      # Lazy initializes the connection
      def connection
        @connection ||= Connection.new(@configuration.connection_options)
      end
    end
  end
end
