require 'spec_helper'

describe Basquiat do
  after(:all) do
    Basquiat.configure do |config|
      config.config_file = File.expand_path('../../support/basquiat.yml', __FILE__)
    end
  end

  it 'should have a version number' do
    expect(Basquiat::VERSION).not_to be_nil
  end

  it '#configure yields to a block' do
    expect { |block| Basquiat.configure(&block) }.to yield_control
  end

  it '#configuration' do
    expect(Basquiat.configuration).to be_a Basquiat::Configuration
  end

  it '#reset' do
    config = Basquiat.configuration
    Basquiat.reset
    expect(Basquiat.configuration).not_to equal(config)
  end
end
