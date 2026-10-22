require 'fileutils'
require 'open3'

class EventoMosaicGenerator
  def initialize(evento:, pasta_param:)
    @evento = evento
    @pasta_param = pasta_param.to_s.strip
    @pasta_nome = @pasta_param.presence || 'Sem pasta'
  end

  attr_reader :pasta_param, :pasta_nome

  def call(progress_callback: nil)
    selection = build_image_paths
    image_paths = Array(selection[:paths])
    raise StandardError, 'Nao ha imagens validas associadas a esta pasta para gerar mosaico.' if image_paths.empty?

    output_dir = Rails.root.join(
      'tmp',
      'mosaico_dji',
      "evento_#{@evento.id}",
      safe_file_fragment(pasta_nome),
      Time.current.strftime('%Y%m%d_%H%M%S_%6N')
    )
    FileUtils.mkdir_p(output_dir)

    emit_progress(
      progress_callback,
      stage: 'render',
      status: 'started',
      progress: 40,
      message: 'Montando mosaico com o motor DJI atualizado...'
    )

    mosaic_image_path = run_mosaic_engine!(input_dir: selection[:input_dir], output_dir: output_dir)

    preview_url = publish_mosaic_preview(
      evento_id: @evento.id,
      pasta_nome: pasta_nome,
      mosaic_path: mosaic_image_path
    )

    emit_progress(
      progress_callback,
      stage: 'render',
      status: 'completed',
      progress: 95,
      message: 'Mosaico gerado com sucesso.'
    )

    {
      preview_url: preview_url,
      pasta_param: pasta_param,
      pasta_nome: pasta_nome,
      optimization: {
        enabled: false,
        source_total_count: selection[:source_total_count],
        source_zenital_count: selection[:source_zenital_count],
        preselected_count: selection[:selected_count],
        preselection_mode: selection[:selection_mode]
      }
    }
  end

  private

  def run_mosaic_engine!(input_dir:, output_dir:)
    return run_mosaic_engine_cloud_run!(input_dir: input_dir, output_dir: output_dir) if MosaicRendering::Settings.cloud_run?

    run_mosaic_engine_local!(input_dir: input_dir, output_dir: output_dir)
  end

  def run_mosaic_engine_cloud_run!(input_dir:, output_dir:)
    renderer = MosaicRendering::CloudRun.new
    renderer.render!(input_dir: input_dir, output_dir: output_dir)
  rescue MosaicRendering::BackendError => e
    raise StandardError, "Falha ao montar mosaico no Cloud Run: #{e.message}"
  end

  def run_mosaic_engine_local!(input_dir:, output_dir:)
    script_path = Rails.root.join('lib', 'mosaico', 'mosaico_dji.py')
    raise StandardError, 'Motor de mosaico DJI nao encontrado na aplicacao.' unless File.file?(script_path)

    python_bin = ENV.fetch(
      'MOSAIC_PYTHON_BIN',
      ENV.fetch('P2PNET_PYTHON_BIN', 'python3')
    ).to_s.presence || 'python3'

    command = [
      python_bin,
      script_path.to_s,
      input_dir.to_s,
      '--output-dir',
      output_dir.to_s,
      '--overwrite',
      '--no-zip'
    ]

    stdout, stderr, status = Open3.capture3(*command)
    unless status.success?
      details = stderr.presence || stdout.presence || 'sem detalhes retornados pelo processo Python'
      details = details.lines.last(10).join.strip.truncate(1200)
      raise StandardError, "Falha ao montar mosaico com o motor DJI (codigo #{status.exitstatus}): #{details}"
    end

    Rails.logger.info("Motor de mosaico DJI concluido: #{stdout.lines.last(3).join.strip}") if stdout.present?
    mosaic_path = output_dir.join('mosaico.jpg')
    unless File.file?(mosaic_path) && File.size(mosaic_path).positive?
      raise StandardError, 'Falha ao gerar mosaico: o novo motor nao produziu uma imagem de saida valida.'
    end

    mosaic_path.to_s
  end

  def build_image_paths
    imagens = if pasta_param.present?
                @evento.imagens.where(pasta: pasta_param)
              else
                @evento.imagens.where(pasta: [nil, ''])
              end

    imagens = imagens.to_a
    tolerance = AppSetting.zenith_tolerance_degrees
    zenitais = imagens.select { |imagem| imagem.zenital?(tolerance_degrees: tolerance) }
    imagens_selecionadas = zenitais.any? ? zenitais : imagens
    selection_mode = zenitais.any? ? 'zenital_only' : 'fallback_all'

    input_dir = Rails.root.join(
      'tmp',
      'mosaico_dji_inputs',
      "evento_#{@evento.id}",
      safe_file_fragment(pasta_nome),
      Time.current.strftime('%Y%m%d_%H%M%S_%6N')
    )
    FileUtils.mkdir_p(input_dir)

    paths = imagens_selecionadas.each_with_index.filter_map do |imagem, index|
      next unless imagem.arquivo.attached?

      path = materialize_attachment_path_for_mosaic(imagem.arquivo, input_dir, index)
      path if path.present? && File.exist?(path)
    end

    {
      paths: paths,
      input_dir: input_dir,
      source_total_count: imagens.size,
      source_zenital_count: zenitais.size,
      selected_count: imagens_selecionadas.size,
      selection_mode: selection_mode
    }
  end

  def materialize_attachment_path_for_mosaic(attachment, input_dir, index)
    blob = attachment.blob
    return nil unless blob.content_type.to_s.start_with?('image/')

    extension = blob.filename.extension_with_delimiter
    extension = '.jpg' if extension.blank?
    base_name = safe_file_fragment(blob.filename.base)
    file_name = format('%05d_%s%s', index, base_name, extension)
    target_path = input_dir.join(file_name)

    File.binwrite(target_path, blob.download)
    target_path.to_s
  rescue StandardError
    nil
  end

  def publish_mosaic_preview(evento_id:, pasta_nome:, mosaic_path:)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    output_dir = MosaicStorage.ensure_event_dir(evento_id: evento_id, pasta_nome: pasta_nome)
    target_path = output_dir.join("mosaic_#{timestamp}_compressed.jpg")
    FileUtils.cp(mosaic_path, target_path)

    MosaicStorage.sync_to_other_roots(target_path)
    MosaicStorage.url_for_absolute_path(target_path)
  end

  def emit_progress(callback, payload)
    callback&.call(payload)
  rescue StandardError
    nil
  end

  def safe_file_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end
end
