# frozen_string_literal: true

require 'spec_helper'
require 'multi_background_Job/middleware/unique_job_middleware'

RSpec.describe MultiBackgroundJob::Middleware::UniqueJobMiddleware, freeze_at: [2020, 7, 2, 12, 30, 50] do
  let(:worker) do
    MultiBackgroundJob::Worker.new('DummyWorker',
      queue: 'mailer',
    ).with_job_jid('dummy123')
  end
  let(:service) { :sidekiq }
  let(:now) { Time.now.to_f }

  before do
    described_class.bootstrap
  end

  after do
    MultiBackgroundJob.config.middleware.clear
  end

  shared_examples 'unique job across' do |across|
    context "with a unique job across #{across}" do
      let(:lock_digest) do
        MultiBackgroundJob::LockDigest.new(service, :mailer, across: across)
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
        end
      end

      it 'adds a lock with 1 hour of TTL and enqueues a new job' do
        redis do |conn|
          conn.del(sidekiq_immediate_name)
          expect(conn.llen(sidekiq_immediate_name)).to eq(0)
          conn.del(lock_digest)
          expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(0)

          result = push!
          expect(result).to eq(
            'args' => [],
            'class' => worker.worker_class,
            'jid' => 'dummy123',
            'created_at' => Time.now.to_f,
            'enqueued_at' => Time.now.to_f,
            'queue' => 'mailer',
            'retry' => true,
            'uniq' => {
              'across' => across.to_s,
              'timeout' => 3_600,
              'unlock_policy' => 'success',
              'ttl' => now + 3_600,
            }
          )
          expect(conn.llen(sidekiq_immediate_name)).to eq(1)
          expect(conn.zcount(lock_digest, 0, now + DAY_IN_SECONDS)).to eq(1)

          lock_id = conn.zrangebyscore(lock_digest, now + 3_600, now + 3_600)[0]
          expect(lock_id).to be_a_kind_of(String)

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
          end
        end
      end
    end
  end

  describe '.call' do
    subject(:push!) { worker.push(to: service) }

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
