# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MultiBackgroundJob do
  describe '.[] class method' do
    after { reset_config! }

    context 'without definition' do
      specify do
        described_class.configure { |c| c.strict = false }

        worker = described_class['DummyWorker']
        expect(worker).to be_an_instance_of(MultiBackgroundJob::Worker)
        expect(worker.options).to eq({})
      end
    end

    context 'with workers definition' do
      before do
        MultiBackgroundJob.config.workers = {
          'DummyWorker' => { 'queue' => 'custom' },
          'Other' => { 'queue' => 'other' },
        }
      end

      it 'loads worker options from global config' do
        worker = described_class['DummyWorker']
        expect(worker).to be_an_instance_of(MultiBackgroundJob::Worker)
        expect(worker.options).to eq(queue: 'custom')
      end

      it 'does not allow build a worker when strict mode is active' do
        described_class.configure { |config| config.strict = false }
        worker = described_class['MissingWorker']
        expect(worker).to be_an_instance_of(MultiBackgroundJob::Worker)

        described_class.configure { |config| config.strict = true }
        expect { described_class['MissingWorker'] }.to raise_error(MultiBackgroundJob::NotDefinedWorker)
      end
    end
  end

  describe '.jid class method' do
    specify do
      expect(described_class.jid).to be_a_kind_of(String)
      expect(described_class.jid).not_to eq(described_class.jid)
      expect(described_class.jid.size).to eq(24)
    end
  end

  describe '.config class method' do
    it { expect(described_class.config).to be_an_instance_of(MultiBackgroundJob::Config) }
  end

  describe '.configure' do
    after { reset_config! }

    it 'overwrites default config value' do
      described_class.config.redis_pool_size = 10
      described_class.config.redis_pool_timeout = 2

      described_class.configure { |config| config.redis_pool_size = 20 }
      expect(described_class.config.redis_pool_size).to eq(20)
      expect(described_class.config.redis_pool_timeout).to eq(2)
    end

    it 'starts a fresh redis pool' do
      pool = described_class.redis_pool
      3.times { expect(described_class.redis_pool).to eql(pool) }
      described_class.configure { |config| config.redis_pool_size = 1 }
      expect(described_class.redis_pool).not_to eql(pool)
    end
  end
end
