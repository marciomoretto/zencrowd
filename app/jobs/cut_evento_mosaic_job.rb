class CutEventoMosaicJob < ApplicationJob
  queue_as :default

  def perform(evento_id, pasta_nome, source_path, rows, cols, progress_key)
    evento = Evento.find_by(id: evento_id)
    unless evento
      write_failed(evento_id: evento_id, progress_key: progress_key, error: 'Evento nao encontrado para corte do mosaico.')
      return
    end

    cutter = MosaicTempGridCutter.new(
      source_path: source_path,
      rows: rows,
      cols: cols,
      evento_id: evento.id,
      pasta_nome: pasta_nome
    )

    progress_callback = lambda do |payload|
      EventoMosaicCutProgressStore.write(
        evento_id: evento.id,
        progress_key: progress_key,
        payload: {
          status: 'running',
          processed_count: payload[:processed_count].to_i,
          total_count: payload[:total_count].to_i,
          message: payload[:message].presence || 'Contando cabecas nos recortes...'
        }
      )
    end

    result = cutter.call(progress_callback: progress_callback)
    unless result.success?
      write_failed(evento_id: evento.id, progress_key: progress_key, error: result.error)
      return
    end

    ActiveRecord::Base.transaction do
      record = evento.pasta_head_estimates.find_or_initialize_by(pasta_nome: pasta_nome)
      record.estimated_heads = result.total_heads.to_i
      record.save!

      evento.mosaic_piece_head_counts.where(pasta_nome: pasta_nome).delete_all

      rows = Array(result.piece_counts)
      if rows.any?
        now = Time.current
        evento.mosaic_piece_head_counts.insert_all!(
          rows.map do |piece|
            {
              evento_id: evento.id,
              pasta_nome: pasta_nome,
              row_index: piece[:row_index].to_i,
              col_index: piece[:col_index].to_i,
              estimated_heads: piece[:estimated_heads].to_i,
              created_at: now,
              updated_at: now
            }
          end
        )
      end
    end

    EventoMosaicCutProgressStore.write(
      evento_id: evento.id,
      progress_key: progress_key,
      payload: {
        status: 'completed',
        processed_count: result.files_count.to_i,
        total_count: result.files_count.to_i,
        total_heads: result.total_heads.to_i,
        piece_counts: Array(result.piece_counts).map { |piece| piece.slice(:row_index, :col_index, :estimated_heads) },
        output_dir: result.output_dir,
        message: "Contagem concluida: #{result.total_heads} cabecas estimadas."
      }
    )
  rescue StandardError => e
    Rails.logger.error("Erro no corte/contagem do mosaico para evento ##{evento_id}: #{e.class} - #{e.message}")
    write_failed(evento_id: evento_id, progress_key: progress_key, error: e.message)
  end

  private

  def write_failed(evento_id:, progress_key:, error:)
    EventoMosaicCutProgressStore.write(
      evento_id: evento_id,
      progress_key: progress_key,
      payload: {
        status: 'failed',
        processed_count: 0,
        total_count: 0,
        error: error,
        message: error
      }
    )
  end
end
