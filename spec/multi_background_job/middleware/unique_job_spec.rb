# frozen_string_literal: true

require 'spec_helper'
require 'multi_background_job/middleware/unique_job'

RSpec.describe MultiBackgroundJob::Middleware::UniqueJob, freeze_at: [2020, 7, 2, 12, 30, 50] do
  describe '.bootstrap' do
    before do
      MultiBackgroundJob.config.middleware.clear
    end

    after do
      MultiBackgroundJob.config.middleware.clear
    end

    it 'loads and configure the external middleware for sidekiq' do
      described_class.bootstrap(service: :sidekiq)
      expect { MultiBackgroundJob.const_get('Middleware::UniqueJob::Sidekiq::Worker') }.not_to raise_error
      expect(MultiBackgroundJob.config.middleware.exists?(described_class)).to eq(true)
    end

    it 'does not load UniqueJob middleware and raise an error' do
      expect { described_class.bootstrap(service: :invalid) }.to raise_error(
        MultiBackgroundJob::Error,
        %[UniqueJob is not supported for the `:invalid' service. Supported options are: `:sidekiq'.]
      )
      expect(MultiBackgroundJob.config.middleware.exists?(described_class)).to eq(false)
    end
  end

  describe '.unique_job_lock_id' do
    let(:worker) { MultiBackgroundJob::Worker.new('DummyWorker') }

    specify do
      expect(described_class.new.send(:unique_job_lock_id, worker)).to eq(
        Digest::SHA256.hexdigest('["DummyWorker",[]]'),
      )
    end

    specify do
      expect(described_class.new.send(:unique_job_lock_id, worker.with_args(1))).to eq(
        Digest::SHA256.hexdigest('["DummyWorker",[1]]'),
      )
    end

    specify do
      expect(described_class.new.send(:unique_job_lock_id, worker.with_args(user_id: 1))).to eq(
        Digest::SHA256.hexdigest('["DummyWorker",[{"user_id":1}]]'),
      )
    end
  end

  describe '.unique_job_lock', freeze_at: [2020, 7, 1, 22, 24, 40] do
    specify do
      worker = MultiBackgroundJob::Worker.new('DummyWorker')
      expect(described_class.new.send(:unique_job_lock, worker: worker, service: :sidekiq)).to eq(nil)
    end

    specify do
      worker = MultiBackgroundJob::Worker.new('DummyWorker', uniq: true)
      job_lock = described_class.new.send(:unique_job_lock, worker: worker, service: :sidekiq)

      expect(job_lock).to be_an_instance_of(MultiBackgroundJob::Lock)
    end

    specify do
      worker = MultiBackgroundJob::Worker.new('DummyWorker', uniq: true, service: :sidekiq)
      job_lock = described_class.new.send(:unique_job_lock, worker: worker, service: :sidekiq)

      expect(job_lock).to eq(described_class.new.send(:unique_job_lock, worker: worker, service: :sidekiq))
      expect(job_lock).not_to eq(described_class.new.send(:unique_job_lock, worker: worker, service: :faktory))
    end
  end

end
