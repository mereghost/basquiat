module Basquiat
  module Adapters
    class RabbitMq
      # Responsible for dealing with the overall configuration of the RabbitMQ adapter
      class Configuration
        using Basquiat::HashRefinements

        def initialize
          @options = { connection:
                                  { hosts: ['localhost'],
                                    port:  5672,
                                    auth:  { user: 'guest', password: 'guest' }
                                  },
                       queue:     {
                         name:    Basquiat.configuration.queue_name,
                         options: { durable: true } },
                       exchange:  {
                         name:    Basquiat.configuration.exchange_name,
                         options: { durable: true } },
                       publisher: { confirm: true, persistent: false },
                       requeue:   { enabled: false } }
        end

        def base_options
          @options
        end

        # Merges the user supplied options with the base ones
        # @param user_opts [Hash{Symbol=>Object}]
        # @option user_opts [Hash{Symbol=>Object}] :connection see {Connection#initialize}
        # @option user_opts [Hash{Symbol=>Object}] :queue
        # @option user_opts [Hash{Symbol=>Object}] :exchange
        # @option user_opts [Hash{Symbol=>Object}] :publisher
        # @option user_opts [Hash{Symbol=>Object}] :requeue
        # @return [Hash] the configuration option hash
        def merge_user_options(**user_opts)
          @options.merge!(user_opts)
        end

        # @return [Hash] the connection options
        def connection_options
          @options[:connection]
        end

        # @return [Hash] the session options
        def session_options
          { exchange:  @options[:exchange],
            publisher: @options[:publisher],
            queue:     @options[:queue] }.deep_merge(strategy.session_options)
        end

        # @return [BaseStrategy] the requeue strategy or {BasicAcknowledge} if none is configured
        def strategy
          requeue = @options[:requeue]
          return BasicAcknowledge unless requeue[:enabled]
          @strategy ||= RabbitMq.strategy(requeue[:strategy].to_sym)
          @strategy.setup(requeue[:options] || {})
          @strategy
        end
      end
    end
  end
end
