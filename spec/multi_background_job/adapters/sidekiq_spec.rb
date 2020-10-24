# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MultiBackgroundJob::Adapters::Sidekiq do
  let(:worker_class) { 'DummyWorker' }
  let(:worker_args) { ['User', 1] }
  let(:worker_opts) { {} }
  let(:worker_job_id) { '123xyz' }
  let(:worker) do
    MultiBackgroundJob::Worker
      .new(worker_class, **worker_opts)
      .with_job_jid(worker_job_id)
      .with_args(*worker_args)
  end
  let(:model) { described_class.new(worker) }
  let(:redis_dataset) do
    {
      standard_name: model.send(:immediate_queue_name),
      scheduled_name: model.send(:scheduled_queue_name),
    }
  end

  before do
    MultiBackgroundJob.configure { |c| c.workers = { 'DummyWorker' => {} } }
  end

  after do
    reset_config!
  end

  describe '.push class method' do
    specify do
      expect(described_class).to receive(:new).with(worker).and_return(double(push: 'ok'))
      expect(described_class.push(worker)).to eq('ok')
    end
  end

  describe '.push instance method', freeze_at: [2020, 7, 2, 12, 30, 50] do
    subject(:push!) { model.push }

    let(:now) { Time.now.to_f }

    context 'with a standard job' do
      it 'adds a valid sidekiq hash to redis' do
        redis do |conn|
          conn.del(redis_dataset[:standard_name])
          conn.del(redis_dataset[:scheduled_name])
          expect(conn.llen(redis_dataset[:standard_name])).to eq(0)
          expect(conn.zcount(redis_dataset[:scheduled_name], 0, now + DAY_IN_SECONDS)).to eq(0)

          result = push!
          expect(result).to eq(
            'args' => worker_args,
            'class' => worker_class,
            'jid' => worker_job_id,
            'created_at' => Time.now.to_f,
            'enqueued_at' => Time.now.to_f,
            'queue' => 'default',
            'retry' => true,
          )
          expect(conn.llen(redis_dataset[:standard_name])).to eq(1)
          expect(conn.zcount(redis_dataset[:scheduled_name], 0, now + DAY_IN_SECONDS)).to eq(0)

          raw_payload = conn.lpop(redis_dataset[:standard_name])
          expect(MultiJson.dump(result, mode: :compat)).to eq(raw_payload)
        end
      end
    end

    context 'with a scheduled job' do
      let(:worker_opts) { { queue: 'mailer' } }

      before do
        worker.at(Time.now + HOUR_IN_SECONDS)
      end

      it 'adds a valid sidekiq hash to redis' do
        redis do |conn|
          conn.del(redis_dataset[:standard_name])
          conn.del(redis_dataset[:scheduled_name])
          expect(conn.llen(redis_dataset[:standard_name])).to eq(0)
          expect(conn.zcount(redis_dataset[:scheduled_name], 0, now + DAY_IN_SECONDS)).to eq(0)

          result = push!
          expect(result).to eq(
            'args' => worker_args,
            'class' => worker_class,
            'jid' => worker_job_id,
            'created_at' => Time.now.to_f,
            'enqueued_at' => Time.now.to_f,
            'queue' => 'mailer',
            'retry' => true,
          )
          expect(conn.llen(redis_dataset[:standard_name])).to eq(0)
          expect(conn.zcount(redis_dataset[:scheduled_name], 0, now + DAY_IN_SECONDS)).to eq(1)

          raw_payload = conn.zrangebyscore(redis_dataset[:scheduled_name], now, '+inf')[0]
          expect(MultiJson.dump(result, mode: :compat)).to eq(raw_payload)
        end
      end
    end
  end

  describe '.coerce_to_worker class method', freeze_at: [2020, 7, 2, 12, 30, 50] do
    specify do
      expect { described_class.coerce_to_worker(nil) }.to raise_error(MultiBackgroundJob::Error, 'invalid payload')
      expect { described_class.coerce_to_worker('test') }.to raise_error(MultiBackgroundJob::Error, 'invalid payload')
      expect { described_class.coerce_to_worker({}) }.to raise_error(MultiBackgroundJob::Error, 'invalid payload')
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker')
      not_expected = MultiBackgroundJob::Worker.new('OtherWorker')
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker', retry: false)
      not_expected = MultiBackgroundJob::Worker.new('DummyWorker', retry: true)
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'retry' => false,
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker', queue: 'foo')
      not_expected = MultiBackgroundJob::Worker.new('DummyWorker', queue: 'bar')
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'queue' => 'foo',
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker', uniq: { across: :systemwide, timeout: HOUR_IN_SECONDS, unlock_policy: :start })
      not_expected = MultiBackgroundJob::Worker.new('DummyWorker', uniq: { across: :queue, timeout: HOUR_IN_SECONDS, unlock_policy: :start })
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'uniq' => {
            'across' => 'systemwide',
            'timeout' => 3_600,
            'unlock_policy' => 'start',
            'ttl' => Time.now + 3_600,
          },
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker').with_args(1)
      not_expected = MultiBackgroundJob::Worker.new('DummyWorker').with_args([1, 2])
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'args' => [1],
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker').with_job_jid('123')
      not_expected = MultiBackgroundJob::Worker.new('DummyWorker').with_job_jid('456')
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'jid' => '123',
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker').created_at((Time.now - (MINUTE_IN_SECONDS * 10)).to_f)
      not_expected = MultiBackgroundJob::Worker.new('DummyWorker').created_at((Time.now - (MINUTE_IN_SECONDS * 11)).to_f)
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'created_at' => (Time.now - (MINUTE_IN_SECONDS * 10)).to_f,
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker').enqueued_at((Time.now - (MINUTE_IN_SECONDS * 10)).to_f)
      not_expected = MultiBackgroundJob::Worker.new('DummyWorker').enqueued_at((Time.now - (MINUTE_IN_SECONDS * 11)).to_f)
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'enqueued_at' => (Time.now - (MINUTE_IN_SECONDS * 10)).to_f,
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker.new('DummyWorker').at((Time.now + (MINUTE_IN_SECONDS * 10)).to_f)
      not_expected = MultiBackgroundJob::Worker.new('DummyWorker').at((Time.now + (MINUTE_IN_SECONDS * 11)).to_f)
      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'at' => (Time.now + (MINUTE_IN_SECONDS * 10)).to_f,
          'created_at' => (Time.now + (MINUTE_IN_SECONDS * 10)).to_f,
        },
      )
      expect(actual).to eq(expected)
      expect(actual).not_to eq(not_expected)
    end

    specify do
      expected = MultiBackgroundJob::Worker
        .new('DummyWorker', queue: 'other', retry: true)
        .with_args(123)
        .with_job_jid('16c4c1ee56d858d1a5d0cacb')
        .created_at(1589474236)
        .enqueued_at(1589474236)

      actual = described_class.coerce_to_worker(
        {
          'class' => 'DummyWorker',
          'args'  => [123],
          'retry' =>  true,
          'queue' => 'other',
          'jid'   => '16c4c1ee56d858d1a5d0cacb',
          'created_at' => 1589474236.0,
          'enqueued_at' => 1589474236.0,
        },
      )
      expect(actual).to eq(expected)
    end
  end

  def redis
    MultiBackgroundJob.redis_pool.with do |conn|
      yield conn
    end
  end
end
