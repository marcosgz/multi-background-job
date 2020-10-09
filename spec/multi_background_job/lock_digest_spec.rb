require 'spec_helper'
require 'multi_background_job/lock_digest'

RSpec.describe MultiBackgroundJob::LockDigest do
  describe '.to_s' do
    context 'without namespace' do
      before do
        MultiBackgroundJob.config.redis_namespace = nil
      end

      after { reset_config! }

      specify do
        expect(described_class.new('foo', across: :queue).to_s).to eq('uniqueness:foo')
        expect(described_class.new('sidekiq', 'foo', across: :queue).to_s).to eq('uniqueness:sidekiq:foo')
      end

      specify do
        expect(described_class.new('foo', across: :systemwide).to_s).to eq('uniqueness')
        expect(described_class.new('sidekiq', 'foo', across: :systemwide).to_s).to eq('uniqueness:sidekiq')
      end

      specify do
        expect{ described_class.new('foo', across: :undefined).to_s }.to raise_error(
          MultiBackgroundJob::Error,
          'Could not resolve the lock digest using across :undefined. Valid options are :systemwide and :queue',
        )
        expect{ described_class.new('sidekiq', 'foo', across: :undefined).to_s }.to raise_error(MultiBackgroundJob::Error)
      end
    end

    context 'without namespace' do
      before do
        MultiBackgroundJob.config.redis_namespace = 'multi-bg-job-test'
      end

      after { reset_config! }

      specify do
        expect(described_class.new('foo', across: :queue).to_s).to eq('multi-bg-job-test:uniqueness:foo')
        expect(described_class.new('sidekiq', 'foo', across: :queue).to_s).to eq('multi-bg-job-test:uniqueness:sidekiq:foo')
      end

      specify do
        expect(described_class.new('foo', across: :systemwide).to_s).to eq('multi-bg-job-test:uniqueness')
        expect(described_class.new('sidekiq', 'foo', across: :systemwide).to_s).to eq('multi-bg-job-test:uniqueness:sidekiq')
      end

      specify do
        expect{ described_class.new('foo', across: :undefined).to_s }.to raise_error(
          MultiBackgroundJob::Error,
          'Could not resolve the lock digest using across :undefined. Valid options are :systemwide and :queue',
        )
        expect{ described_class.new('sidekiq', 'foo', across: :undefined).to_s }.to raise_error(MultiBackgroundJob::Error)
      end
    end
  end
end
