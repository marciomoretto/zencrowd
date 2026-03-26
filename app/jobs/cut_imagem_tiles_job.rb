class CutImagemTilesJob < ApplicationJob
  queue_as :default

  def perform(imagem_id, uploader_id, rows, cols, replace_existing, progress_key, feedback_key)
    imagem = Imagem.find_by(id: imagem_id)
    uploader = User.find_by(id: uploader_id)

    unless imagem && uploader
      write_failed_progress(
        imagem_id: imagem_id,
        progress_key: progress_key,
        feedback_key: feedback_key,
        rows: rows,
        cols: cols,
        error: 'Imagem ou usuário não encontrado para processar o corte.'
      )
      return
    end

    total_count = rows.to_i * cols.to_i

    cutter = ImagemTileCutter.new(
      imagem: imagem,
      uploader: uploader,
      rows: rows,
      cols: cols
    )

    result = cutter.call(replace_existing: replace_existing) do |progress|
      ImagemCutProgressStore.write(
        imagem_id: imagem.id,
        progress_key: progress_key,
        payload: {
          status: 'running',
          processed_count: progress[:processed_count].to_i,
          total_count: progress[:total_count].to_i,
          created_count: progress[:created_count].to_i,
          feedback_key: feedback_key,
          message: progress[:message].presence || "Processando tile #{progress[:processed_count]} de #{progress[:total_count]}..."
        }
      )
    end

    if result.success?
      feedback = ImagemCutFeedbackBuilder.build(result)

      ImagemCutProgressStore.write_feedback(
        imagem_id: imagem.id,
        feedback_key: feedback_key,
        payload: {
          flash_level: feedback[:level].to_s,
          message: feedback[:message]
        }
      )

      ImagemCutProgressStore.write(
        imagem_id: imagem.id,
        progress_key: progress_key,
        payload: {
          status: 'completed',
          processed_count: total_count,
          total_count: total_count,
          created_count: result.created_count,
          feedback_key: feedback_key,
          message: feedback[:message]
        }
      )
    else
      write_failed_progress(
        imagem_id: imagem.id,
        progress_key: progress_key,
        feedback_key: feedback_key,
        rows: rows,
        cols: cols,
        error: result.error
      )
    end
  rescue StandardError => e
    Rails.logger.error("Erro no corte assíncrono da imagem ##{imagem_id}: #{e.class} - #{e.message}")

    write_failed_progress(
      imagem_id: imagem_id,
      progress_key: progress_key,
      feedback_key: feedback_key,
      rows: rows,
      cols: cols,
      error: 'Falha interna ao processar o corte dos tiles.'
    )
  end

  private

  def write_failed_progress(imagem_id:, progress_key:, feedback_key:, rows:, cols:, error:)
    total_count = rows.to_i * cols.to_i

    ImagemCutProgressStore.write_feedback(
      imagem_id: imagem_id,
      feedback_key: feedback_key,
      payload: {
        flash_level: 'alert',
        message: error
      }
    )

    ImagemCutProgressStore.write(
      imagem_id: imagem_id,
      progress_key: progress_key,
      payload: {
        status: 'failed',
        processed_count: 0,
        total_count: total_count,
        created_count: 0,
        feedback_key: feedback_key,
        error: error,
        message: error
      }
    )
  end
end
