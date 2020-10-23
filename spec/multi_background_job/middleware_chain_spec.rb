require 'spec_helper'

RSpec.describe MultiBackgroundJob::MiddlewareChain do
  let(:model) { described_class.new }

  describe '.add' do
    let(:middleware) do
      Class.new { def call(*); end; }
    end

    specify do
      expect(model.entries).to eq([])
      model.add(middleware)
      expect(model.entries[0]).to be_an_instance_of(described_class::Entry)
      expect(model.entries[0].klass).to eq(middleware)
      expect(model.entries[0].args).to eq([])
    end

    specify do
      expect(model.entries).to eq([])
      model.add(middleware, debug: true)
      expect(model.entries[0]).to be_an_instance_of(described_class::Entry)
      expect(model.entries[0].klass).to eq(middleware)
      expect(model.entries[0].args).to eq([{debug: true}])
    end

    specify do
      expect(model.entries).to eq([])
      model.add(middleware)
      expect(model.entries.size).to eq(1)
      model.add(middleware)
      expect(model.entries.size).to eq(1)
      expect(model.entries[0].args).to eq([])
      model.add(middleware, debug: true)
      expect(model.entries.size).to eq(1)
      expect(model.entries[0].args).to eq([{debug: true}])
    end
  end

  describe '.remove' do
    let(:middleware1) do
      Class.new { def call(*); end; }
    end
    let(:middleware2) do
      Class.new { def call(*); end; }
    end

    specify do
      expect{ model.remove(nil) }.not_to raise_error
      model.add(middleware2)
      model.add(middleware1)
      expect(model.entries.size).to eq(2)
      expect{ model.remove(middleware1) }.not_to raise_error
      expect(model.entries.size).to eq(1)
    end
  end

  describe '.prepend' do
    let(:middleware1) do
      Class.new { def call(*); end; }
    end
    let(:middleware2) do
      Class.new { def call(*); end; }
    end
    let(:middleware3) do
      Class.new { def call(*); end; }
    end

    specify do
      model.add(middleware1)
      model.add(middleware2)
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware2])
      expect(model.prepend(middleware3))
      expect(model.entries.map(&:klass)).to eq([middleware3, middleware1, middleware2])
    end

    specify do
      model.add(middleware1)
      model.add(middleware2)
      model.add(middleware3)
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware2, middleware3])
      expect(model.prepend(middleware3))
      expect(model.entries.map(&:klass)).to eq([middleware3, middleware1, middleware2])
    end
  end

  describe '.insert_before' do
    let(:middleware1) do
      Class.new { def call(*); end; }
    end
    let(:middleware2) do
      Class.new { def call(*); end; }
    end
    let(:middleware3) do
      Class.new { def call(*); end; }
    end

    specify do
      model.add(middleware1)
      model.add(middleware2)
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware2])
      expect(model.insert_before(middleware2, middleware3))
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware3, middleware2])
    end

    specify do
      model.add(middleware1)
      expect(model.entries.map(&:klass)).to eq([middleware1])
      expect(model.insert_before(middleware2, middleware3))
      expect(model.entries.map(&:klass)).to eq([middleware3, middleware1])
    end

    specify do
      model.add(middleware1)
      model.add(middleware2)
      model.add(middleware3)
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware2, middleware3])
      expect(model.insert_before(middleware2, middleware3))
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware3, middleware2])
    end
  end

  describe '.clear' do
    let(:middleware1) do
      Class.new { def call(*); end; }
    end
    let(:middleware2) do
      Class.new { def call(*); end; }
    end

    before do
      model.add(middleware1)
      model.add(middleware2)
    end

    specify do
      expect(model.entries.size).to eq(2)
      model.clear
      expect(model.entries.size).to eq(0)
    end
  end

  describe '.insert_after' do
    let(:middleware1) do
      Class.new { def call(*); end; }
    end
    let(:middleware2) do
      Class.new { def call(*); end; }
    end
    let(:middleware3) do
      Class.new { def call(*); end; }
    end

    specify do
      model.add(middleware1)
      model.add(middleware2)
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware2])
      expect(model.insert_after(middleware2, middleware3))
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware2, middleware3])
    end

    specify do
      model.add(middleware1)
      expect(model.entries.map(&:klass)).to eq([middleware1])
      expect(model.insert_after(middleware2, middleware3))
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware3])
    end

    specify do
      model.add(middleware1)
      model.add(middleware2)
      model.add(middleware3)
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware2, middleware3])
      expect(model.insert_after(middleware1, middleware3))
      expect(model.entries.map(&:klass)).to eq([middleware1, middleware3, middleware2])
    end
  end

  describe '.exists' do
    let(:middleware1) do
      Class.new { def call(*); end; }
    end
    let(:middleware2) do
      Class.new { def call(*); end; }
    end

    specify do
      expect(model.exists?(middleware1)).to eq(false)
      model.add(middleware1)
      expect(model.exists?(middleware1)).to eq(true)
      expect(model.exists?(middleware2)).to eq(false)
    end
  end

  describe '.retrieve' do
    let(:middleware_with_args) do
      Class.new { def initialize(arg); @arg = arg end; }
    end
    let(:middleware_without_args) do
      Class.new { def initialize(); end; }
    end

    specify do
      model.add(middleware_without_args)
      expect(model.retrieve[0]).to be_an_instance_of(middleware_without_args)
    end

    specify do
      model.add(middleware_with_args, 'ok')
      expect(model.retrieve[0]).to be_an_instance_of(middleware_with_args)
      expect(model.retrieve[0].instance_variable_get(:@arg)).to eq('ok')
    end
  end

  describe '.invoke' do
    let(:middleware1) do
      Class.new do
        def call(arg)
          result = yield
          result.push(arg)
          result
        end
      end
    end

    let(:middleware2) do
      Class.new do
        def call(arg)
          return false if arg == 3

          result = yield
          result.push(arg + 1)
          result
        end
      end
    end

    specify do
      model.add(middleware1)
      executed = false
      result = model.invoke(1) do
        executed = true
        []
      end
      expect(executed).to eq(true)
      expect(result).to eq([1])
    end

    specify do
      model.add(middleware1)
      model.add(middleware2)
      executed = false
      result = model.invoke(1) do
        executed = true
        []
      end
      expect(executed).to eq(true)
      expect(result).to eq([1, 2])
    end

    specify do
      model.add(middleware1)
      model.add(middleware2)
      executed = false
      result = model.invoke(3) do
        executed = true
        []
      end
      expect(executed).to eq(false)
      expect(result).to eq(false)
    end
  end
end
