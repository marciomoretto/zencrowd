require 'csv'
require 'zip'
require 'tempfile'

class DatasetsController < ApplicationController
  before_action :authenticate_user!, only: [:create, :destroy]
  before_action :authorize_admin!, only: [:create, :destroy]
  before_action :set_dataset, only: [:download, :destroy]

  def index
    @datasets = Dataset.includes(:creator, archive_attachment: :blob).order(created_at: :desc)
    @dataset = Dataset.new(created_at: Time.zone.today.beginning_of_day)
  end

  def create
    @dataset = Dataset.new(dataset_params)
    @dataset.creator = current_user
    @dataset.created_at = dataset_creation_datetime

    if @dataset.created_at.nil?
      flash[:alert] = 'Data de criação inválida.'
      return redirect_to datasets_path
    end

    if @dataset.name.blank?
      flash[:alert] = 'Informe um nome para o dataset.'
      return redirect_to datasets_path
    end

    eligible_tiles = Tile
      .where(status: %i[approved payment_requested paid legacy])
      .includes(:tile_point_set, annotations: :annotation_points)
      .order(:id)
      .to_a

    if eligible_tiles.empty?
      flash[:alert] = 'Nenhum tile elegível encontrado (aprovado, solicitação de pagamento, pago ou legado).'
      return redirect_to datasets_path
    end

    summary = summarize_tiles_and_points(eligible_tiles)
    @dataset.tiles_count = summary[:tiles_count]
    @dataset.points_count = summary[:points_count]

    begin
      ActiveRecord::Base.transaction do
        @dataset.save!
        attach_archive!(@dataset, eligible_tiles)
      end

      flash[:notice] = 'Dataset criado com sucesso.'
      redirect_to datasets_path
    rescue StandardError => e
      Rails.logger.error("Falha ao criar dataset: #{e.class} - #{e.message}")
      flash[:alert] = "Não foi possível criar o dataset: #{e.message}"
      redirect_to datasets_path
    end
  end

  def download
    unless @dataset.archive.attached?
      redirect_to datasets_path, alert: 'Arquivo ZIP deste dataset não está disponível.'
      return
    end

    blob = @dataset.archive.blob
    send_data @dataset.archive.download,
              filename: dataset_archive_filename(@dataset),
              type: blob.content_type.presence || 'application/zip',
              disposition: 'attachment'
  end

  def destroy
    if @dataset.destroy
      redirect_to datasets_path, notice: 'Dataset removido com sucesso.'
    else
      redirect_to datasets_path, alert: @dataset.errors.full_messages.to_sentence.presence || 'Não foi possível remover o dataset.'
    end
  end

  private

  def dataset_params
    params.require(:dataset).permit(:name)
  end

  def dataset_creation_datetime
    raw_date = params.dig(:dataset, :created_on).to_s.strip
    selected_date = raw_date.present? ? Date.iso8601(raw_date) : Time.zone.today
    Time.zone.local(selected_date.year, selected_date.month, selected_date.day)
  rescue ArgumentError
    nil
  end

  def set_dataset
    @dataset = Dataset.find(params[:id])
  end

  def attach_archive!(dataset, tiles)
    zip_path = nil
    tile_files = eligible_tile_files!(tiles)

    Tempfile.create(["dataset_#{dataset.id}_", '.zip'], Rails.root.join('tmp')) do |tmpfile|
      zip_path = tmpfile.path

      Zip::OutputStream.open(zip_path) do |zip|
        zip.put_next_entry('points.csv')
        zip.write(generate_points_csv(tiles))

        tile_files.each do |tile, image_path|
          original_name = File.basename(tile.original_filename.to_s)
          ext = File.extname(original_name).presence || '.jpg'
          base = File.basename(original_name, '.*').presence || "tile_#{tile.id}"
          entry_name = "images/tile_#{tile.id}_#{base.parameterize}#{ext}"

          zip.put_next_entry(entry_name)
          zip.write(File.binread(image_path))
        end
      end

      dataset.archive.attach(
        io: File.open(zip_path, 'rb'),
        filename: dataset_archive_filename(dataset),
        content_type: 'application/zip'
      )
    end
  ensure
    File.delete(zip_path) if zip_path.present? && File.exist?(zip_path)
  end

  def generate_points_csv(tiles)
    CSV.generate(headers: true) do |csv|
      csv << %w[tile_id arquivo status axis point_id x y]

      tiles.each do |tile|
        points_payload = points_payload_for(tile)

        if points_payload[:points].empty?
          csv << [tile.id, tile.original_filename, tile.status, points_payload[:axis], nil, nil, nil]
          next
        end

        points_payload[:points].each do |point|
          csv << [
            tile.id,
            tile.original_filename,
            tile.status,
            points_payload[:axis],
            point[:id] || point['id'],
            point[:x] || point['x'],
            point[:y] || point['y']
          ]
        end
      end
    end
  end

  def points_payload_for(tile)
    point_set = tile.tile_point_set
    if point_set.present?
      return {
        axis: point_set.axis.presence || 'image',
        points: Array(point_set.points)
      }
    end

    latest_annotation = tile.annotations
      .includes(:annotation_points)
      .order(created_at: :desc)
      .detect { |annotation| annotation.annotation_points.any? }

    return { axis: 'image', points: [] } unless latest_annotation

    {
      axis: 'image',
      points: latest_annotation.annotation_points.order(:id).map do |point|
        { id: point.id, x: point.x, y: point.y }
      end
    }
  end

  def summarize_tiles_and_points(tiles)
    points_count = tiles.sum do |tile|
      points_payload_for(tile)[:points].size
    end

    {
      tiles_count: tiles.size,
      points_count: points_count
    }
  end

  def eligible_tile_files!(tiles)
    resolved = tiles.map { |tile| [tile, image_file_path(tile)] }
    missing = resolved.select { |(_, path)| path.blank? }.map { |(tile, _)| tile.id }

    if missing.any?
      raise "Não foi possível gerar o dataset: arquivo ausente para tile(s) ##{missing.join(', #')}"
    end

    resolved
  end

  def dataset_archive_filename(dataset)
    version = dataset.name.to_s.strip.presence || "dataset-#{dataset.id}"
    "zencrowd-bd #{version}.zip"
  end

  # Resolve com seguranca o caminho do arquivo do tile.
  # Aceita caminhos relativos e absolutos, desde que estejam dentro de Rails.root/storage.
  def image_file_path(image)
    return nil if image.storage_path.blank?

    raw_path = Pathname.new(image.storage_path)
    full_path = raw_path.absolute? ? raw_path : Rails.root.join(raw_path)
    full_path = full_path.cleanpath

    storage_root = Rails.root.join('storage').cleanpath.to_s
    return nil unless full_path.to_s.start_with?(storage_root)
    return nil unless File.file?(full_path)

    full_path.to_s
  end
end
