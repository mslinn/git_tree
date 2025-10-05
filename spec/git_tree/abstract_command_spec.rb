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
  end

  subject(:command) { DummyCommand.new(args) }

  let(:args) { [] }

  describe 'initialization' do
    it 'loads config and sets initial verbosity' do
      mock_config = instance_double(GitTree::Config, verbosity: 99)
      allow(GitTree::Config).to receive(:new).and_return(mock_config)
      allow(Logging).to receive(:verbosity=)

      described_class.new

      expect(GitTree::Config).to have_received(:new)
      expect(Logging).to have_received(:verbosity=).with(99)
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
  end
end
