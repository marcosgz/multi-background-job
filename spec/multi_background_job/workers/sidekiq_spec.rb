# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MultiBackgroundJob::Workers::Sidekiq' do
  describe 'MultiBackgroundJob#for' do
    context 'with default settings' do
      let(:worker) do
        Class.new do
          extend MultiBackgroundJob.for(:sidekiq)

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
          retry: 15,
        )
      end
    end

    context 'with global Sidekiq available' do
      let(:worker_module) { Module.new }

      before do
        Object.const_set(:Sidekiq, Class.new do
          def self.default_worker_options
            {
              'queue' => 'dummy',
              'retry' => 0,
            }
          end
        end)
        Object.const_get(:Sidekiq).const_set(:Worker, worker_module)
      end

      after do
        Object.send(:remove_const, :Sidekiq) if Object.constants.include?(:Sidekiq)
      end

      let(:worker) do
        Class.new do
          extend MultiBackgroundJob.for(:sidekiq)

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
        expect(worker.included_modules).to include(worker_module)
      end
    end
  end
end
