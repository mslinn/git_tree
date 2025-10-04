require 'spec_helper'
require_relative '../../lib/commands/git_exec'

describe GitTree::ExecCommand do
  subject(:command) { described_class.new(args) }

  let(:mock_walker) { instance_double(GitTreeWalker) }
  let(:mock_runner) { instance_double(CommandRunner) }
  let(:command_to_run) { 'ls -l' }
  let(:repo_dir) { '/fake/root/repo1' }

  before do
    # Inject test doubles before each test
    command.walker = mock_walker
    command.runner = mock_runner

    # Stub the process method to yield a fake directory for testing
    allow(mock_walker).to receive(:process).and_yield(nil, repo_dir, 0, nil)
  end

  describe '#run' do
    context 'with insufficient arguments' do
      let(:args) { [command_to_run] } # Only one argument

      it 'calls help and exits' do
        # Stub exit to prevent test suite termination
        allow(command).to receive(:exit)
        expect(command).to have_received(:help).with('At least one root and a command must be specified.')
        command.run
      end
    end

    context 'when the shell command is successful' do
      let(:args) { ['/fake/root', command_to_run] }
      let(:command_output) { "file1.txt\nfile2.txt" }

      it 'executes the command and logs output to stdout' do
        allow(mock_runner).to receive(:run).with(command_to_run, repo_dir)
                                            .and_return([command_output, double(success?: true)])

        expect(command).to have_received(:log_stdout).with(command_output)
        expect(command).not_to have_received(:log) # Should not log to stderr

        command.run
      end
    end

    context 'when the shell command fails' do
      let(:args) { ['/fake/root', command_to_run] }
      let(:error_output) { 'ls: not found' }

      it 'executes the command and logs output to stderr' do
        allow(mock_runner).to receive(:run).with(command_to_run, repo_dir)
                                            .and_return([error_output, double(success?: false)])

        expect(command).to have_received(:log).with(QUIET, error_output, :red)
        expect(command).not_to have_received(:log_stdout)

        command.run
      end
    end

    context 'when the runner raises an exception' do
      let(:args) { ['/fake/root', command_to_run] }
      let(:error_message) { 'A critical error occurred' }

      it 'rescues the exception and logs an error message to stderr' do
        allow(mock_runner).to receive(:run).with(command_to_run, repo_dir).and_raise(StandardError, error_message)

        expected_log_message = "Error: '#{error_message}' from executing '#{command_to_run}' in #{repo_dir}"
        expect(command).to have_received(:log).with(QUIET, expected_log_message, :red)
        expect(command).not_to have_received(:log_stdout)

        command.run
      end
    end
  end
end
