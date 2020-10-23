# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MultiBackgroundJob::UniqueJob do

  let(:across_option) { :queue }
  let(:timeout_option) { WEEK_IN_SECONDS }
  let(:unlock_policy_option) { :success }

  describe '.initialize' do
    context 'without arguments' do
      specify do
        model = described_class.new
        expect(model.across).to eq(across_option)
        expect(model.timeout).to eq(timeout_option)
        expect(model.unlock_policy).to eq(unlock_policy_option)
      end
    end

    context 'with custom :across option' do
      specify do
        expect { described_class.new(across: :invalid) }.to raise_error(
          MultiBackgroundJob::Error, 'Invalid `across: :invalid` option. Only [:queue, :systemwide] are allowed.'
        )
      end

      specify do
        model = described_class.new(across: :queue)
        expect(model.across).to eq(:queue)
      end

      specify do
        model = described_class.new(across: :systemwide)
        expect(model.across).to eq(:systemwide)
      end

      specify do
        model = described_class.new(across: 'systemwide')
        expect(model.across).to eq(:systemwide)
      end
    end

    context 'with custom :unlock_policy option' do
      specify do
        expect { described_class.new(unlock_policy: :invalid) }.to raise_error(
          MultiBackgroundJob::Error, 'Invalid `unlock_policy: :invalid` option. Only [:success, :start] are allowed.'
        )
      end

      specify do
        model = described_class.new(unlock_policy: :success)
        expect(model.unlock_policy).to eq(:success)
      end

      specify do
        model = described_class.new(unlock_policy: :start)
        expect(model.unlock_policy).to eq(:start)
      end

      specify do
        model = described_class.new(unlock_policy: 'start')
        expect(model.unlock_policy).to eq(:start)
      end
    end

    context 'with custom :timeout option' do
      specify do
        model = described_class.new(timeout: -1 )
        expect(model.timeout).to eq(timeout_option)
      end

      specify do
        model = described_class.new(timeout: 10)
        expect(model.timeout).to eq(10)
      end
    end
  end

  describe '.to_hash' do
    subject { model.to_hash }

    context 'with default options' do
      let(:model) { described_class.new }

      specify do
        is_expected.to eq(
          across: across_option,
          timeout: timeout_option,
          unlock_policy: unlock_policy_option,
        )
      end
    end

    context 'with custom options' do
      let(:model) { described_class.new(across: 'systemwide', timeout: 10, unlock_policy: 'start') }

      specify do
        is_expected.to eq(
          across: :systemwide,
          timeout: 10,
          unlock_policy: :start,
        )
      end
    end
  end

  describe '.as_json' do
    subject { model.as_json }

    context 'with default options' do
      let(:model) { described_class.new }

      specify do
        is_expected.to eq(
          'across' => across_option.to_s,
          'timeout' => timeout_option,
          'unlock_policy' => unlock_policy_option.to_s,
        )
      end
    end

    context 'with custom options' do
      let(:model) { described_class.new(across: 'systemwide', timeout: 10, unlock_policy: 'start') }

      specify do
        is_expected.to eq(
          'across' => 'systemwide',
          'timeout' => 10,
          'unlock_policy' => 'start',
        )
      end
    end
  end

  describe '.eql?' do
    specify do
      expect(described_class.new(across: 'systemwide', timeout: 10, unlock_policy: 'start')).to eq(
        described_class.new(across: 'systemwide', timeout: 10, unlock_policy: 'start')
      )
    end

    specify do
      expect(described_class.new(across: 'systemwide', timeout: 10, unlock_policy: :start)).to eq(
        described_class.new(across: :systemwide, timeout: 10, unlock_policy: 'start')
      )
    end

    specify do
      expect(described_class.new(across: :queue, timeout: 10, unlock_policy: :start)).not_to eq(
        described_class.new(across: :systemwide, timeout: 10, unlock_policy: 'start')
      )
    end

    specify do
      expect(described_class.new(across: :systemwide, timeout: 11, unlock_policy: :start)).not_to eq(
        described_class.new(across: :systemwide, timeout: 10, unlock_policy: 'start')
      )
    end

    specify do
      expect(described_class.new(across: :systemwide, timeout: 10, unlock_policy: :success)).not_to eq(
        described_class.new(across: :systemwide, timeout: 10, unlock_policy: :start)
      )
    end
  end
end