# frozen_string_literal: true

require 'spec_helper'
require 'multi_background_job/middleware/unique_job'

RSpec.describe MultiBackgroundJob::Middleware::UniqueJob, freeze_at: [2020, 7, 2, 12, 30, 50] do
  let(:worker_class) do
    Class.new do
      def self.name
        'DummyWorker'
      end
    end
  end
  let(:worker) do
    MultiBackgroundJob::Worker.new(worker_class.name,
      queue: 'mailer',
    ).with_job_jid('dummy123')
  end
  let(:service) { :sidekiq }
  let(:now) { Time.now.to_f }

  after do
    MultiBackgroundJob.config.middleware.clear
  end

  describe '.bootstrap' do
    it 'loads and configure the external middleware for sidekiq' do
      expect { MultiBackgroundJob.const_get('Middleware::UniqueJob::Sidekiq::Worker') }.to raise_error(NameError)
      described_class.bootstrap(service: :sidekiq)
      expect { MultiBackgroundJob.const_get('Middleware::UniqueJob::Sidekiq::Worker') }.not_to raise_error
      expect(MultiBackgroundJob.config.middleware.exists?(described_class)).to eq(true)
    end

    it 'does not load UniqueJob middleware and raise an error' do
      expect { MultiBackgroundJob.const_get('Middleware::UniqueJob::Invalid') }.to raise_error(NameError)
      expect { described_class.bootstrap(service: :invalid) }.to raise_error(
        MultiBackgroundJob::Error,
        %[UniqueJob is not supported for the `:invalid' service. Supported options are: `:sidekiq'.]
      )
      expect(MultiBackgroundJob.config.middleware.exists?(described_class)).to eq(false)
    end
  end

  shared_examples 'unique job across' do |across|
    subject(:push!) { worker.push(to: service) }

    context "with a unique job across #{across}" do
      let(:lock_digest) do
        MultiBackgroundJob::LockDigest.new(service, :mailer, across: across).to_s
      end

      before do
        worker.unique(across: across, timeout: HOUR_IN_SECONDS)
      end

      it 'does not push job when active uniqueness lock exist' do
        redis do |conn|
          conn.del(sidekiq_immediate_name)
          expect(conn.llen(sidekiq_immediate_name)).to eq(0)
          conn.del(lock_digest)
          expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(0)

          # Adds a lock_id
          lock_id = Digest::SHA256.hexdigest('["DummyWorker",[]]')
          conn.zadd(lock_digest, now+1, lock_id)
          conn.zadd(lock_digest, now-2, '123')
          conn.zadd(lock_digest, now-1, '456')
          expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(3)

          result = push!
          expect(result).to eq(false)
          expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(1)
          ttl = conn.zscore(lock_digest, lock_id)
          expect(ttl.to_i).to eq(now.to_i+1)

          job = worker.job.merge(
            'uniq' => {
              'across' => across.to_s,
              'timeout' => 3_600,
              'unlock_policy' => 'success',
              'lock' => {
                'ttl' => now + 3_600,
                'digest' => lock_digest,
                'lock_id' => lock_id,
              }
            }
          )

          # Removes the lock after job execution
          expect { |y| MultiBackgroundJob::Middleware::UniqueJob::Sidekiq::Worker.new.call(worker_class, job, 'mailer', &y) }.to yield_control
          expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(0)
        end
      end

      it 'adds a lock with 1 hour of TTL and enqueues a new job' do
        redis do |conn|
          conn.del(sidekiq_immediate_name)
          expect(conn.llen(sidekiq_immediate_name)).to eq(0)
          conn.del(lock_digest)
          expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(0)

          result = push!
          expect(result.dig('uniq', 'across')).to eq(across.to_s)
          expect(result.dig('uniq', 'timeout')).to eq(3_600)
          expect(result.dig('uniq', 'unlock_policy')).to eq('success')
          expect(result.dig('uniq', 'lock', 'ttl')).to eq(now + 3_600)
          expect(result.dig('uniq', 'lock', 'digest')).to eq(lock_digest)
          expect(result.dig('uniq', 'lock', 'lock_id')).to be_a_kind_of(String)

          expect(conn.llen(sidekiq_immediate_name)).to eq(1)
          expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(1)

          lock_id = conn.zrangebyscore(lock_digest, now + 3_600, now + 3_600)[0]
          expect(lock_id).to be_a_kind_of(String)
          expect(result.dig('uniq', 'lock', 'lock_id')).to eq(lock_id)

          # Adds more expired jobs to be flushed
          conn.zadd(lock_digest, now-2, '123')
          conn.zadd(lock_digest, now-1, '456')
          travel_to = Time.now + HOUR_IN_SECONDS + 1
          Timecop.travel(travel_to) do
            new_result = worker.push(to: :sidekiq)
            expect(conn.llen(sidekiq_immediate_name)).to eq(2)
            expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(1)
            ttl = conn.zscore(lock_digest, lock_id)
            expect(ttl.to_i).to eq(travel_to.to_i + 3_600)

            # Removes the lock after job execution
            expect { |y| MultiBackgroundJob::Middleware::UniqueJob::Sidekiq::Worker.new.call(worker_class, result, 'mailer', &y) }.to yield_control
            expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(0)
          end
        end
      end
    end
  end

  describe '.call' do
    before do
      described_class.bootstrap(service: service)
    end

    it_behaves_like('unique job across', :queue)
    it_behaves_like('unique job across', :systemwide)
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

  def redis
    MultiBackgroundJob.redis_pool.with do |conn|
      yield conn
    end
  end

  def sidekiq_immediate_name
    "#{MultiBackgroundJob.config.redis_namespace}:queue:mailer"
  end
end
