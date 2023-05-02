require_relative '../lib/replicate_git_tree'

RSpec.describe('Replicate Git Tree') do
  it 'makes env vars' do
    base = 'demo'
    dirs = ReplicateGitTree.directories_to_process base
    result = ReplicateGitTree.make_env_vars(base, dirs)
    expect(result).to eq <<~END_STR
      cat <<EOF > demo/.evars
      export demo=/mnt/c/work/git/replicate_git_tree/demo
      export proj_a=$demo/proj_a
      export proj_b=$demo/proj_b
      export proj_d=$demo/sub1/proj_d
      export proj_e=$demo/sub1/proj_e
      export proj_f=$demo/sub1/proj_f
      EOF
    END_STR
  end

  it 'finds git repos under a normal directory' do
    dirs = ReplicateGitTree.directories_to_process 'demo'
    expect(dirs).to eq(
      [
        'proj_a',
        'proj_b',
        'sub1/proj_d',
        'sub1/proj_e',
        'sub1/proj_f'
      ]
    )
  end

  it 'finds git repos under a symlinked directory' do
    base = ReplicateGitTree.expand_env '$work'
    dirs = ReplicateGitTree.directories_to_process base
    expect(dirs.length).to be > 5
  end
end
