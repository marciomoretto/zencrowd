require 'rails_helper'
require 'stringio'

RSpec.describe MosaicRendering::PhotoStore do
  let(:objects) { {} }
  let(:bucket) do
    store = objects
    Class.new do
      define_method(:file) { |name| store.key?(name) ? name : nil }
      define_method(:create_file) { |path, name, **_options| store[name] = File.binread(path) }
    end.new
  end
  let(:blobs) do
    Array.new(10) do |index|
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new("foto-#{index}"), filename: "DJI_#{index}.JPG", content_type: 'image/jpeg')
    end
  end

  it 'envia so os blobs que ainda nao estao no bucket, lendo do disco do ActiveStorage' do
    objects["mosaic-photos/#{blobs.first.key}"] = 'antiga'
    progress = []

    sent = described_class.new(bucket: bucket).ensure_uploaded!(blobs, on_progress: ->(done, total) { progress << [done, total] })

    expect(sent).to eq(9)
    expect(objects["mosaic-photos/#{blobs.first.key}"]).to eq('antiga')
    expect(objects["mosaic-photos/#{blobs.last.key}"]).to eq('foto-9')
    expect(progress.last).to eq([10, 10])
  end

  it 'propaga a falha de envio' do
    failing_bucket = Class.new do
      def file(_name) = nil
      def create_file(*) = raise(IOError, 'gcs fora')
    end.new

    expect { described_class.new(bucket: failing_bucket).ensure_uploaded!(blobs.first(2)) }.to raise_error(IOError, 'gcs fora')
  end

  it 'monta a entrada do manifest do worker' do
    blob = blobs.first
    expect(described_class.manifest_entry(blob)).to eq(object: "mosaic-photos/#{blob.key}", key: blob.key, name: 'DJI_0.JPG')
  end
end
