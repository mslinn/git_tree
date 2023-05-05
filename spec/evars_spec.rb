require_relative '../lib/evar'

RSpec.describe(Evars) do
  it 'finds common prefix' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub1/sub2',
      '/root/sub1',
      '/root/sub3/sub1'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq '/root'
  end

  it 'finds common prefix again' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub1/sub2',
      '/root/sub1',
      '/root2/sub3/sub1'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq '/'
  end
end
