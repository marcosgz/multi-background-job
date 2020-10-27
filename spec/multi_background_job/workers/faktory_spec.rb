# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MultiBackgroundJob::Workers::Faktory' do
  describe 'MultiBackgroundJob#for' do
    context 'with default settings' do
      let(:worker) do
        Class.new do
          extend MultiBackgroundJob.for(:faktory)

          def self.name
            'DummyWorker'
          end
        end
      end

      specify do
        expect(worker).to respond_to(:perform_async)
        expect(worker).to respond_to(:perform_in)
        expect(worker).to respond_to(:perform_at)
      end

      specify do
        expect(worker.service_worker_options).to eq(
          queue: 'default',
          retry: 25,
        )
      end

      specify do
        expect(worker.bg_worker_options).to eq({
          service: :faktory,
        })
      end
    end

    context 'with global Faktory available' do
      let(:job_module) { Module.new }

      before do
        stub_const('Faktory', Class.new do
          def self.default_job_options
            {
              'queue' => 'dummy',
              'retry' => 0,
            }
          end
        end)
        stub_const('Faktory::Job', job_module)
      end

      after do
        reset_config!
      end

      let(:worker) do
        Class.new do
          extend MultiBackgroundJob.for(:faktory)

          def self.name
            'DummyWorker'
          end
        end
      end

      specify do
        expect(worker).to respond_to(:perform_async)
        expect(worker).to respond_to(:perform_in)
        expect(worker).to respond_to(:perform_at)
      end

      specify do
        expect(worker.service_worker_options).to eq(
          queue: 'dummy',
          retry: 0,
        )
      end

      specify do
        expect(worker.bg_worker_options).to eq({
          service: :faktory,
        })
      end

      it 'does not overwrite the :queue from configurations' do
        MultiBackgroundJob.config.workers[worker.name] = {
          queue: 'config',
        }
        expect(worker.service_worker_options).to eq(
          queue: 'config',
          retry: 0,
        )
      end

      it 'does not overwrite the :queue from configurations' do
        MultiBackgroundJob.config.workers[worker.name] = {
          retry: 10,
        }
        expect(worker.service_worker_options).to eq(
          queue: 'dummy',
          retry: 10,
        )
      end
    end

    context 'with custom settings' do
      let(:worker1) do
        Class.new do
          extend MultiBackgroundJob.for(:faktory, queue: 'one', retry: 1)

          def self.name
            'DummyWorkerOne'
          end
        end
      end

      let(:worker2) do
        Class.new do
          extend MultiBackgroundJob.for(:faktory, queue: 'two', retry: 2)

          def self.name
            'DummyWorkerTwo'
          end
        end
      end

      after do
        reset_config!
      end

      specify do
        expect(worker1).to respond_to(:perform_async)
        expect(worker2).to respond_to(:perform_async)
        expect(worker1).to respond_to(:perform_in)
        expect(worker2).to respond_to(:perform_in)
        expect(worker1).to respond_to(:perform_at)
        expect(worker1).to respond_to(:perform_at)
      end

      specify do
        expect(worker1.bg_worker_options).to eq({
          queue: 'one',
          retry: 1,
          service: :faktory,
        })
        expect(worker2.bg_worker_options).to eq({
          queue: 'two',
          retry: 2,
          service: :faktory,
        })
      end
    end
  end
end
