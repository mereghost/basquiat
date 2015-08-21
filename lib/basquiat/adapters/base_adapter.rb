require 'delegate'
require 'basquiat/adapters/base_message'

module Basquiat
  module Adapters
    # Base implementation for an adapter
    class Base
      using Basquiat::HashRefinements

      class << self
        def strategies
          @strategies ||= {}
        end

        # Used to register a requeue strategy
        # @param [String,Symbol] config_name the named used on the config file for the Requeue Strategy
        # @param [Class] klass the class name.
        def register_strategy(config_name, klass)
          strategies[config_name.to_sym] = klass
        end

        def strategy(key)
          strategies.fetch(key)
        rescue KeyError
          fail Basquiat::Errors::StrategyNotRegistered
        end
      end

      def initialize(procs: {})
        @options = base_options
        @procs   = procs
        @retries = 0
      end

      def strategies
        self.class.strategies
      end

      # Used to set the options for the adapter. It is merged in
      # to the default_options hash.
      # @param [Hash] opts an adapter dependant hash of options
      def adapter_options(opts)
        @options.deep_merge(opts)
      end

      # Default options for the adapter
      # @return [Hash]
      def base_options
        default_options.merge(Basquiat.configuration.adapter_options)
      end

      def default_options
        {}
      end

      def publish
        fail Basquiat::Errors::SubclassResponsibility
      end

      def subscribe_to
        fail Basquiat::Errors::SubclassResponsibility
      end

      def disconnect
        fail Basquiat::Errors::SubclassResponsibility
      end

      private

      attr_reader :procs, :options
    end
  end
end
