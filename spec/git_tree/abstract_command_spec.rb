require 'spec_helper'
require_relative '../../lib/commands/abstract_command'
require_relative '../../lib/util/log'

describe GitTree::AbstractCommand do
  # Create a minimal concrete class for testing the abstract class's behavior
  class DummyCommand < GitTree::AbstractCommand
    attr_reader :options # Expose for testing

    def run; end

    def help; end # Stub help to prevent exit

    # Expose parse_options for direct testing
    public :parse_options

    # Override run to expose the walker for testing
    def run
      args_for_walker = @args.empty? ? @config.default_roots : @args
      @walker ||= GitTreeWalker.new(args_for_walker, options: @options) # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    # Simulate a subclass that adds its own options
    def parse_options(args)
      super do |opts|
        opts.on("--dummy-opt VALUE", "A dummy option for testing") do |val|
          @options[:dummy] = val
        end
      end
    end
  end

  subject(:command) { DummyCommand.new(args) }

  let(:args) { [] }

  describe 'initialization' do
    let(:mock_config) { instance_double(GitTree::Config, verbosity: 99, default_roots: %w[root1 root2]) }

    it 'loads config and sets initial verbosity' do
      allow(GitTree::Config).to receive(:new).and_return(mock_config)
      allow(Logging).to receive(:verbosity=)

      described_class.new

      expect(GitTree::Config).to have_received(:new)
      expect(Logging).to have_received(:verbosity=).with(99)
    end
  end

  describe 'argument handling' do
    let(:mock_config) { instance_double(GitTree::Config, verbosity: 1, default_roots: %w[configured_root]) }

    it 'uses default_roots from config when no args are given' do
      allow(GitTree::Config).to receive(:new).and_return(mock_config)
      mock_walker = instance_double(GitTreeWalker)
      allow(GitTreeWalker).to receive(:new).and_return(mock_walker)

      command = DummyCommand.new([]) # No arguments
      command.run

      expect(GitTreeWalker).to have_received(:new).with(%w[configured_root], options: {})
    end
  end

  describe '#parse_options' do
    context 'with -q (quiet) option' do
      let(:args) { ['-q', '/some/dir'] }

      it 'sets Logging.verbosity to QUIET' do
        allow(Logging).to receive(:verbosity=)
        command.parse_options(args)
        expect(Logging).to have_received(:verbosity=).with(Logging::QUIET)
      end

      it 'does not add a :quiet key to the options hash' do
        command.parse_options(args)
        expect(command.options).not_to have_key(:quiet)
      end

      it 'removes the option from the args array' do
        command.parse_options(args)
        expect(args).to eq(['/some/dir'])
      end
    end

    context 'with -s (serial) option' do
      let(:args) { ['-s', '/some/dir'] }

      it 'adds a :serial key to the options hash' do
        command.parse_options(args)
        expect(command.options).to have_key(:serial)
        expect(command.options[:serial]).to be true
      end

      it 'removes the option from the args array' do
        command.parse_options(args)
        expect(args).to eq(['/some/dir'])
      end
    end

    context 'with -v (verbose) option' do
      let(:args) { ['-v', '/some/dir'] }

      it 'increments Logging.verbosity' do
        # Set a known initial state
        initial_verbosity = Logging.verbosity
        command.parse_options(args)
        # The implementation is `Logging.verbosity += 1`, so we check the final value.
        expect(Logging.verbosity).to eq(initial_verbosity + 1)
      end

      it 'does not add a :verbose key to the options hash' do
        command.parse_options(args)
        expect(command.options).not_to have_key(:verbose)
      end

      it 'removes the option from the args array' do
        command.parse_options(args)
        expect(args).to eq(['/some/dir'])
      end
    end

    context 'with -h (help) option' do
      let(:args) { ['-h', '/some/dir'] }

      it 'calls the help method' do
        # The DummyCommand has a stubbed `help` method.
        allow(command).to receive(:help)
        command.parse_options(args)
        expect(command).to have_received(:help)
      end
    end

    context 'with a command-specific option' do
      let(:args) { ['--dummy-opt', 'test-value', '/some/dir'] }

      it 'adds the specific option to the options hash' do
        command.parse_options(args)
        expect(command.options).to have_key(:dummy)
        expect(command.options[:dummy]).to eq('test-value')
      end

      it 'removes the option and its value from the args array' do
        command.parse_options(args)
        expect(args).to eq(['/some/dir'])
      end
    end
  end

  context 'when a subclass modifies options during initialization' do
    # This dummy class mimics GitTree::UpdateCommand's behavior of
    # removing a key from the options hash for its own use.
    class ModifyingDummyCommand < GitTree::AbstractCommand
      def initialize(args = ARGV, options: {})
        super
        @internal_dependency = @options.delete(:internal)
      end

      def run
        @walker ||= GitTreeWalker.new(@args, options: @options) # rubocop:disable Naming/MemoizedInstanceVariableName
      end
    end

    it 'does not pass the modified option to the walker' do
      allow(GitTreeWalker).to receive(:new)
      command = ModifyingDummyCommand.new(['/some/dir'], options: { internal: 'dependency' })
      command.run
      expect(GitTreeWalker).to have_received(:new).with(['/some/dir'], options: {})
    end
  end
end
