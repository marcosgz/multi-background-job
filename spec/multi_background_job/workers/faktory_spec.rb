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
    end

    context 'with global Faktory available' do
      let(:job_module) { Module.new }

      before do
        Object.const_set(:Faktory, Class.new do
          def self.default_job_options
            {
              'queue' => 'dummy',
              'retry' => 0,
            }
          end
        end)
        Object.const_get(:Faktory).const_set(:Job, job_module)
      end

      after do
        Object.send(:remove_const, :Faktory) if Object.constants.include?(:Faktory)
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
        expect(worker.included_modules).to include(job_module)
      end
    end
  end
end
