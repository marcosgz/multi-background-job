# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MultiBackgroundJob::Config do
  let(:config) { described_class.new }

  describe 'default values' do
    it { expect(config.redis_pool_size).to eq(5) }
    it { expect(config.redis_pool_timeout).to eq(5) }
    it { expect(config.redis_namespace).to eq('multi-bg') }
    it { expect(config.redis_config).to eq({}) }
    it { expect(config.config_path).to eq(nil) }
  end

  describe '.redis_pool_size=' do
    it 'converts value to interger' do
      config.redis_pool_size = '10'
      expect(config.redis_pool_size).to eq(10)
    end

    it 'does not allow lower than zero' do
      msg = -> (v) { "The #{v.inspect} for redis_pool_size is not valid. It must be greater than zero" }
      expect { config.redis_pool_size = '0' }.to raise_error(MultiBackgroundJob::InvalidConfig, msg.(0))
      expect { config.redis_pool_size = 0 }.to raise_error(MultiBackgroundJob::InvalidConfig, msg.(0))
      expect { config.redis_pool_size = -1 }.to raise_error(MultiBackgroundJob::InvalidConfig, msg.(-1))
    end

    context 'from YAML configuration' do
      before do
        config.instance_variable_set(:@config_from_yaml, { 'redis_pool_size' => '5' })
      end

      it 'loads value and convert to integer' do
        expect(config.redis_pool_size).to eq(5)
      end

      it 'overwrites the YAML value' do
        expect(config.redis_pool_size).to eq(5)
        config.redis_pool_size = 10
        expect(config.redis_pool_size).to eq(10)
      end
    end
  end

  describe '.redis_pool_timeout=' do
    it 'converts value to interger' do
      config.redis_pool_timeout = '10'
      expect(config.redis_pool_timeout).to eq(10)
    end

    it 'does not allow lower than zero' do
      msg = -> (v) { "The #{v.inspect} for redis_pool_timeout is not valid. It must be greater than zero" }
      expect { config.redis_pool_timeout = '0' }.to raise_error(MultiBackgroundJob::InvalidConfig, msg.(0))
      expect { config.redis_pool_timeout = 0 }.to raise_error(MultiBackgroundJob::InvalidConfig, msg.(0))
      expect { config.redis_pool_timeout = -1 }.to raise_error(MultiBackgroundJob::InvalidConfig, msg.(-1))
    end

    context 'from YAML configuration' do
      before do
        config.instance_variable_set(:@config_from_yaml, { 'redis_pool_timeout' => '5' })
      end

      it 'loads value and convert to integer' do
        expect(config.redis_pool_timeout).to eq(5)
      end

      it 'overwrites the YAML value' do
        expect(config.redis_pool_timeout).to eq(5)
        config.redis_pool_timeout = 10
        expect(config.redis_pool_timeout).to eq(10)
      end
    end
  end

  describe '.redis_namespace=' do
    specify do
      expect(config.redis_namespace).to eq('multi-bg')
      config.redis_namespace = 'custom-ns'
      expect(config.redis_namespace).to eq('custom-ns')
    end

    context 'from YAML configuration' do
      before do
        config.instance_variable_set(:@config_from_yaml, { 'redis_namespace' => 'ns' })
      end

      it 'loads default config from YAML' do
        expect(config.redis_namespace).to eq('ns')
      end

      it 'overwrites the YAML value' do
        expect(config.redis_namespace).to eq('ns')
        config.redis_namespace = 'custom-ns'
        expect(config.redis_namespace).to eq('custom-ns')
      end
    end
  end

  describe '.redis_config=' do
    specify do
      expect(config.redis_config).to eq({})
      config.redis_config = 'redis://mymaster'
      expect(config.redis_config).to eq(url: 'redis://mymaster')
    end

    specify do
      expect(config.redis_config).to eq({})
      config.redis_config = { path: '/tmp/redis.sock' }
      expect(config.redis_config).to eq(path: '/tmp/redis.sock')
    end
  end

  describe '.workers' do
    specify do
      expect(config.workers).to eq({})
      config.workers = {
        'DummyWorker' => {}
      }
      expect(config.workers).to eq('DummyWorker' => {})
    end

    it 'symbolize worker options' do
      config.workers = {
        DummyWorker: { 'queue' => 'default' }
      }
      expect(config.workers).to eq('DummyWorker' => { queue: 'default' })
    end

    context 'from YAML configuration' do
      before do
        config.instance_variable_set(:@config_from_yaml, { 'workers' => { 'DummyWorker' => { 'retry' => false, 'queue' => 'dummy' } } })
      end

      it 'loads default config from YAML' do
        expect(config.workers).to eq('DummyWorker' => { retry: false, queue: 'dummy' })
      end

      it 'overwrites the YAML value' do
        expect(config.workers).to eq('DummyWorker' => { retry: false, queue: 'dummy' })
        config.workers['OtherWorker'] = { retry: true }
        expect(config.workers).to eq(
          'DummyWorker' => { retry: false, queue: 'dummy' },
          'OtherWorker' => { retry: true },
        )
      end
    end
  end

  describe '.worker_options' do
    before do
      config.workers = {
        'DummyWorker' => { 'queue' => 'mailing' }
      }
    end

    after { reset_config! }

    it 'returns an empty hash as default' do
      config.strict = false
      expect(config.worker_options('MissingWorker')).to eq({})
    end

    it 'retrieves the options from workers using class_name' do
      config.strict = true
      expect(config.worker_options('DummyWorker')).to eq(queue: 'mailing')
    end

    it 'raises NotDefinedWorker when on strict mode' do
      config.strict = true

      expect { config.worker_options('MissingWorker') }.to raise_error(MultiBackgroundJob::NotDefinedWorker)
    end
  end

  describe '.redis_pool' do
    specify do
      expect(config.redis_pool).to eq(timeout: 5, size: 5)
    end
  end

  describe '.middleware' do
    specify do
      expect(config.middleware).to be_an_instance_of(MultiBackgroundJob::MiddlewareChain)
    end
  end
end
