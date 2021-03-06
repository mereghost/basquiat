# frozen_string_literal: true

require 'basquiat/adapters/rabbitmq_adapter'

RSpec.describe Basquiat::Adapters::RabbitMq::DelayedDelivery do
  let(:adapter) { Basquiat::Adapters::RabbitMq.new }
  let(:base_options) do
    { connection: { hosts: [ENV.fetch('BASQUIAT_RABBITMQ_1_PORT_5672_TCP_ADDR') { 'localhost' }],
                    port:  ENV.fetch('BASQUIAT_RABBITMQ_1_PORT_5672_TCP_PORT') { 5672 } },
      publisher:  { persistent: true } }
  end

  before(:each) do
    adapter.adapter_options(base_options)
    adapter.adapter_options(requeue: { enabled: true, strategy: 'delayed_delivery', options: { retries: 3 } })
    adapter.strategy # initialize the strategy
  end

  after(:each) { remove_queues_and_exchanges(adapter) }

  it 'creates the dead letter exchange' do
    channel = adapter.session.channel
    expect(channel.exchanges.keys).to contain_exactly('basquiat.exchange', 'basquiat.dlx')
  end

  it 'creates the timeout queues' do
    channel = adapter.session.channel
    expect(channel.queues.keys).to contain_exactly('basquiat.ddlq_1', 'basquiat.ddlq_2', 'basquiat.ddlq_4',
                                                   'basquiat.queue', 'basquiat.ddlq_rejected')
  end

  it 'set the message ttl and dead letter exchange for the delayed queues' do
    session = adapter.session
    channel = session.channel
    expect(channel.queues['basquiat.ddlq_1'].arguments)
      .to match(hash_including('x-dead-letter-exchange' => session.exchange.name, 'x-message-ttl' => 1_000))

    expect(channel.queues['basquiat.ddlq_4'].arguments['x-message-ttl']).to eq(4_000)
  end

  it 'binds the delayed queues' do
    session = adapter.session
    channel = session.channel
    expect do
      channel.exchanges['basquiat.dlx'].publish({ data: 'some message' }.to_json, routing_key: '1000.some.event')
      sleep 0.1
    end.to change { channel.queues['basquiat.ddlq_1'].message_count }.by(1)
  end

  it 'associates the event *.queue_name.event.name with event.name' do
    message = ''
    session = adapter.session
    adapter.subscribe_to('some.event', ->(msg) { message = msg[:data].upcase })

    adapter.listen(block: false)
    session.publish('1000.basquiat.queue.some.event', data: 'some message')
    sleep 0.5

    expect(message).to eq('SOME MESSAGE')
  end

  context 'when a message is requeued' do
    it 'is republished with the appropriate routing key' do
      session = adapter.session
      adapter.subscribe_to('some.event', ->(msg) { msg.requeue })
      adapter.listen(block: false)

      expect do
        session.publish('some.event', data: 'some message')
        sleep 0.3
      end.to change { session.channel.queues['basquiat.ddlq_1'].message_count }.by(1)
    end

    it 'goes to the reject queue if a requeue would exceed the maximum timeout' do
      session = adapter.session
      adapter.subscribe_to('some.event', ->(msg) { msg.requeue })
      adapter.listen(block: false)

      expect do
        session.publish('4000.basquiat.queue.some.event', data: 'some message')
        sleep 0.3
      end.to change { session.channel.queues['basquiat.ddlq_rejected'].message_count }.by(1)
    end

    it 'after it expires it is reprocessed by the right queue' do
      analysed = 0
      session  = adapter.session
      adapter.subscribe_to('some.event',
                           lambda do |msg|
                             if analysed == 1
                               msg.ack
                             else
                               analysed += 1
                               msg.requeue
                             end
                           end)
      adapter.listen(block: false)
      session.publish('some.event', data: 'some message')
      sleep 0.5
      expect(analysed).to eq(1)
      expect(session.queue).to_not have_unacked_messages
    end
  end
end
