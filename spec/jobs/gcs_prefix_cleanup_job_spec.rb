require 'rails_helper'

RSpec.describe GcsPrefixCleanupJob do
  let(:files) { Array.new(40) { |index| double("file#{index}", name: "runs/x/r/#{index}.json", delete: true) } }
  let(:bucket) { double('bucket') }

  before do
    allow(bucket).to receive(:files).with(prefix: 'runs/x/').and_return(double(all: nil).tap { |list| allow(list).to receive(:all) { |&block| files.each(&block) } })
    job = described_class.new
    allow(job).to receive(:bucket).and_return(bucket)
    @job = job
  end

  it 'apaga todos os arquivos do prefixo' do
    @job.perform('runs/x/')

    files.each { |file| expect(file).to have_received(:delete) }
  end

  it 'nao apaga nada sem um prefixo de pasta' do
    @job.perform('runs/x')
    @job.perform('')

    expect(bucket).not_to have_received(:files)
  end
end
