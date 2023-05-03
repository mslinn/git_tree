require_relative '../lib/git_tree'

RSpec.describe(GitTree) do
  it 'makes env vars' do
    base = 'demo'
    dirs = described_class.directories_to_process base
    result = described_class.make_env_vars('$work', base, dirs)

    work = described_class.expand_env("$work")
    expected = <<~END_STR
      cat <<EOF > demo/.evars
      export demo=#{work}/git/git_tree/demo
      export proj_a=$demo/proj_a
      export proj_b=$demo/proj_b
      export proj_d=$demo/sub1/proj_d
      export proj_e=$demo/sub1/proj_e
      export proj_f=$demo/sub1/proj_f
      EOF
    END_STR
    expect(result).to eq expected
  end

  it 'finds git repos under a normal directory' do
    dirs = described_class.directories_to_process 'demo'
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
    base = described_class.expand_env '$work'
    dirs = described_class.directories_to_process base
    expect(dirs.length).to be > 5
  end
end
