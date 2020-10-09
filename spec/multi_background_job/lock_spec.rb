require 'spec_helper'

RSpec.describe MultiBackgroundJob::Lock, freeze_at: [2020, 7, 1, 22, 24, 40] do
  let(:ttl) { Time.now.to_f + HOUR_IN_SECONDS }
  let(:digest) { [MultiBackgroundJob.config.redis_namespace, 'multi-bg-test', 'uniqueness-lock'].join(':') }
  let(:job_id) { 'abc123' }
  let(:model) { described_class.new(digest: digest, ttl: ttl, job_id: job_id) }

  describe '.lock' do
    specify do
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.del(digest)
        expect(conn.zcount(digest, 0, ttl)).to eq(0)

        expect(model.lock).to eq(true)
        expect(conn.zcount(digest, 0, ttl)).to eq(1)
        expect(model.lock).to eq(false)
        expect(conn.zcount(digest, 0, ttl)).to eq(1)
      end
    end

    specify do
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.del(digest)
        expect(model.lock).to eq(true)

        travel_to = Time.at(ttl)
        expect(conn.zcount(digest, 0, ttl)).to eq(1)

        Timecop.travel(travel_to) do
          new_ttl = ttl + HOUR_IN_SECONDS
          new_model = described_class.new(digest: model.digest, job_id: model.job_id, ttl: new_ttl)
          expect(new_model.lock).to eq(false)
          expect(conn.zcount(digest, 0, new_ttl)).to eq(1)
          expect(conn.zcount(digest, 0, ttl)).to eq(0)
        end
      end
    end
  end

  describe '.unlock' do
    specify do
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.del(digest)
        expect(conn.zcount(digest, 0, ttl)).to eq(0)
        expect(model.unlock).to eq(false)

        conn.zadd(digest, ttl, job_id)
        expect(conn.zcount(digest, 0, ttl)).to eq(1)

        expect(model.unlock).to eq(true)
        expect(conn.zcount(digest, 0, ttl)).to eq(0)
      end
    end
  end

  describe '.locked?' do
    specify do
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.del(digest)
        expect(model.locked?).to eq(false)

        conn.zadd(digest, ttl, job_id)
        expect(model.locked?).to eq(true)

        expect(model.unlock).to eq(true)
        expect(model.locked?).to eq(false)
      end
    end

    specify do
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.del(digest)
        expect(model.locked?).to eq(false)

        conn.zadd(digest, ttl, job_id)
        expect(model.locked?).to eq(true)

        travel_to = Time.at(ttl)
        expect(conn.zcount(digest, 0, travel_to.to_f)).to eq(1)
        Timecop.travel(travel_to) do
          expect(model.locked?).to eq(false)
          expect(conn.zcount(digest, 0, travel_to.to_f)).to eq(0)
        end
      end
    end
  end

  describe '.flush_expired_members class method' do
    specify do
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.del(digest)
      end
      expect { described_class.flush_expired_members(digest) }.not_to raise_error
    end

    specify do
      expect { described_class.flush_expired_members(nil) }.not_to raise_error
    end

    specify do
      MultiBackgroundJob.redis_pool.with do |conn|
        conn.del(digest)
        expect { described_class.flush_expired_members(digest, redis: conn) }.not_to raise_error
        expect { described_class.flush_expired_members(nil, redis: conn) }.not_to raise_error
      end
    end

    specify do
      MultiBackgroundJob.redis_pool.with do |conn|
        lock_queue1 = described_class.new(digest: digest + '1', ttl: ttl, job_id: job_id).tap(&:lock)
        lock_queue2 = described_class.new(digest: digest + '2', ttl: ttl, job_id: job_id).tap(&:lock)
        expect(conn.zcount(lock_queue1.digest, 0, ttl)).to eq(1)
        expect(conn.zcount(lock_queue2.digest, 0, ttl)).to eq(1)

        described_class.flush_expired_members(lock_queue1.digest)
        expect(conn.zcount(lock_queue1.digest, 0, ttl)).to eq(1)
        expect(conn.zcount(lock_queue2.digest, 0, ttl)).to eq(1)

        travel_to = Time.at(ttl)
        Timecop.travel(travel_to) do
          described_class.flush_expired_members(lock_queue1.digest)
          expect(conn.zcount(lock_queue1.digest, 0, ttl)).to eq(0)
          expect(conn.zcount(lock_queue2.digest, 0, ttl)).to eq(1)
        end
      end
    end
  end
end
