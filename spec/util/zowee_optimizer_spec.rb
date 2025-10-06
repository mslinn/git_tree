require_relative 'spec_helper'
require_relative '../lib/util/zowee_optimizer'

describe ZoweeOptimizer do
  context 'with no initial variables' do
    let(:optimizer) { described_class.new }

    context 'with a simple nested structure' do
      let(:paths) { ['/a', '/a/b', '/a/b/c'] }

      it 'optimizes definitions correctly' do
        expected = [
          'export a=/a',
          'export b=$a/b',
          'export c=$b/c'
        ]
        expect(optimizer.optimize(paths, [])).to eq(expected)
      end
    end

    context 'with multiple branches from a common root' do
      let(:paths) { ['/a/b', '/a/b/c', '/a/b/d'] }

      it 'reuses the common parent variable' do
        expected = [
          'export b=/a/b',
          'export c=$b/c',
          'export d=$b/d'
        ]
        expect(optimizer.optimize(paths, [])).to eq(expected)
      end
    end

    context 'with unrelated paths' do
      let(:paths) { ['/x/y', '/m/n'] }

      it 'creates absolute path definitions' do
        expect(optimizer.optimize(paths, [])).to eq(['export y=/x/y', 'export n=/m/n'])
      end
    end
  end

  context 'with initial variables' do
    let(:initial_vars) { { '$work' => ['/path/to/work'] } }
    let(:optimizer) { described_class.new(initial_vars) }
    let(:paths) { ['/path/to/work/project_a', '/path/to/work/project_b'] }

    it 'uses the initial variables for substitution' do
      expect(optimizer.optimize(paths, ['$work'])).to eq(['export project_a=$work/project_a', 'export project_b=$work/project_b'])
    end
  end
end
