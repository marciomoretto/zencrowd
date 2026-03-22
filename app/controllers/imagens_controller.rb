require_dependency Rails.root.join('app/services/imagem_metadata_extractor').to_s
require_dependency Rails.root.join('app/services/imagem_tile_cutter').to_s

class ImagensController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!, except: [:show]
  before_action :authorize_admin_or_reviewer!, only: [:show]
  before_action :set_imagem, only: [:show, :update, :destroy, :cortar, :progresso_corte]
  before_action :load_eventos, only: [:show, :update]

  # GET /imagens
  def index
    @cidade_filter = cidade_filter_param
    @sort = sort_param
    @direction = direction_param
    @cidades = Imagem.where.not(cidade: [nil, '']).distinct.order(:cidade).pluck(:cidade)

    scope = Imagem
      .left_outer_joins(:imagem_tiles)
      .preload(:evento)
      .select('imagens.*, COUNT(imagem_tiles.id) AS tiles_count')
      .group('imagens.id')

    scope = scope.where(cidade: @cidade_filter) if @cidade_filter.present?

    @imagens = paginate_scope(scope.order(Arel.sql(sort_order_sql(@sort, @direction))))
  end

  # GET /imagens/new
  def new
    @imagem = Imagem.new
  end

  # POST /imagens
  def create
    attrs = imagem_params.to_h.symbolize_keys.compact_blank
    tile_ids = normalize_tile_ids(attrs.delete(:tile_ids))
    metadata = ::ImagemMetadataExtractor.extract(attrs[:arquivo])

    imagem_attrs = default_imagem_attributes
                  .merge(metadata[:normalized] || {})
                  .merge(attrs.except(:exif_metadata, :xmp_metadata))

    @imagem = Imagem.new(
      imagem_attrs.merge(
        exif_metadata: metadata[:exif] || {},
        xmp_metadata: metadata[:xmp] || {}
      )
    )
    @imagem.tile_ids = tile_ids if tile_ids.present?

    if @imagem.save
      redirect_to imagem_path(@imagem), notice: 'Imagem enviada com sucesso!'
    else
      flash.now[:alert] = @imagem.errors.full_messages.join(', ')
      render :new, status: :unprocessable_entity
    end
  rescue ActionController::ParameterMissing
    @imagem = Imagem.new
    flash.now[:alert] = 'Selecione um arquivo de imagem.'
    render :new, status: :unprocessable_entity
  end

  # GET /imagens/:id
  def show
    @tiles = paginate_scope(@imagem.tiles.order(created_at: :desc))
    apply_cut_feedback_flash!
  end

  # PATCH /imagens/:id
  def update
    association_attrs = imagem_evento_associacao_attrs
    evento_id = evento_associacao_id

    if evento_id.present? && Evento.where(id: evento_id).none?
      flash.now[:alert] = 'Evento selecionado invalido.'
      return render :show, status: :unprocessable_entity
    end

    if @imagem.update(association_attrs.merge(evento_id: evento_id.presence))
      redirect_to imagem_path(@imagem), notice: 'Evento da imagem atualizado com sucesso.'
    else
      flash.now[:alert] = @imagem.errors.full_messages.join(', ')
      render :show, status: :unprocessable_entity
    end
  end

  # POST /imagens/:id/cortar
  def cortar
    rows = params[:rows].to_i
    cols = params[:cols].to_i

    unless valid_grid_size?(rows, cols)
      respond_to do |format|
        format.html { redirect_to imagem_path(@imagem), alert: 'Linhas e colunas devem estar entre 1 e 4.' }
        format.json { render json: { error: 'Linhas e colunas devem estar entre 1 e 4.' }, status: :unprocessable_entity }
      end
      return
    end

    replace_existing = @imagem.tiles.exists?

    respond_to do |format|
      format.html do
        result = cut_image_synchronously(rows: rows, cols: cols, replace_existing: replace_existing)

        if result.success?
          feedback = ImagemCutFeedbackBuilder.build(result)

          if feedback[:level] == :alert
            redirect_to imagem_path(@imagem), alert: feedback[:message]
          else
            redirect_to imagem_path(@imagem), notice: feedback[:message]
          end
        else
          redirect_to imagem_path(@imagem), alert: result.error
        end
      end

      format.json do
        progress_key = SecureRandom.uuid
        feedback_key = SecureRandom.uuid
        total_count = rows * cols

        ImagemCutProgressStore.write(
          imagem_id: @imagem.id,
          progress_key: progress_key,
          payload: {
            status: 'queued',
            processed_count: 0,
            total_count: total_count,
            created_count: 0,
            feedback_key: feedback_key,
            message: 'Corte enfileirado.'
          }
        )

        CutImagemTilesJob.perform_later(
          @imagem.id,
          current_user.id,
          rows,
          cols,
          replace_existing,
          progress_key,
          feedback_key
        )

        render json: {
          progress_key: progress_key,
          feedback_key: feedback_key,
          total_count: total_count,
          status_url: progresso_corte_imagem_path(@imagem, key: progress_key),
          show_url: imagem_path(@imagem, cut_feedback_key: feedback_key)
        }, status: :accepted
      end
    end
  end

  # GET /imagens/:id/progresso_corte?key=...
  def progresso_corte
    progress_key = params[:key].to_s
    progress = ImagemCutProgressStore.read(imagem_id: @imagem.id, progress_key: progress_key)

    if progress.blank?
      render json: { status: 'not_found', error: 'Progresso de corte não encontrado.' }, status: :not_found
    else
      render json: progress, status: :ok
    end
  end

  # DELETE /imagens/:id
  def destroy
    if @imagem.destroy
      redirect_back fallback_location: new_imagem_path, notice: 'Imagem removida com sucesso!'
    else
      errors = @imagem.errors.full_messages.presence || ['Nao foi possivel remover a imagem.']
      redirect_back fallback_location: imagem_path(@imagem), alert: errors.join(', ')
    end
  end

  private

  def set_imagem
    @imagem = Imagem.includes(:tiles).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = 'Imagem nao encontrada.'
    redirect_to new_imagem_path
  end

  def imagem_params
    params.require(:imagem).permit(
      :arquivo,
      :data_hora,
      :gps_location,
      :cidade,
      :local,
      :nome_do_evento,
      :posicao,
      tile_ids: []
    )
  end

  def normalize_tile_ids(raw_tile_ids)
    ids = Array(raw_tile_ids).reject(&:blank?)
    return [] if ids.empty?

    Tile.where(id: ids).pluck(:id)
  end

  def default_imagem_attributes
    {
      data_hora: Time.current.change(sec: 0),
      gps_location: '0.000000,0.000000',
      cidade: 'Nao informada',
      local: 'Nao informado'
    }
  end

  def evento_associacao_params
    params.fetch(:imagem, {}).permit(:evento_id, :evento_autocomplete, :pasta)
  end

  def imagem_evento_associacao_attrs
    attrs = {}
    return attrs unless params.fetch(:imagem, {}).key?(:pasta)

    attrs[:pasta] = evento_associacao_params[:pasta].to_s.strip.presence
    attrs
  end

  def evento_associacao_id
    params = evento_associacao_params
    return params[:evento_id] if params[:evento_id].present?

    typed_value = params[:evento_autocomplete].to_s.strip
    return nil if typed_value.blank?

    match = typed_value.match(/#(\d+)\z/)
    return match[1] if match

    Evento.find_by(nome: typed_value)&.id
  end

  def load_eventos
    @eventos = Evento.order(:nome)
  end

  def authorize_admin_or_reviewer!
    authorize_role!(:admin, :reviewer)
  end

  def cidade_filter_param
    cidade = params[:cidade].to_s.strip
    cidade.presence
  end

  def sort_param
    sort = params[:sort].to_s
    %w[id data_hora tiles_count].include?(sort) ? sort : 'data_hora'
  end

  def direction_param
    params[:direction].to_s.downcase == 'asc' ? :asc : :desc
  end

  def sort_order_sql(sort, direction)
    direction_sql = direction == :asc ? 'ASC' : 'DESC'

    case sort
    when 'id'
      "imagens.id #{direction_sql}"
    when 'tiles_count'
      "COUNT(imagem_tiles.id) #{direction_sql}, imagens.id DESC"
    else
      "imagens.data_hora #{direction_sql}"
    end
  end

  def cut_image_synchronously(rows:, cols:, replace_existing:)
    cutter = ::ImagemTileCutter.new(
      imagem: @imagem,
      uploader: current_user,
      rows: rows,
      cols: cols
    )

    cutter.call(replace_existing: replace_existing)
  end

  def valid_grid_size?(rows, cols)
    rows.between?(ImagemTileCutter::MIN_GRID_SIZE, ImagemTileCutter::MAX_GRID_SIZE) &&
      cols.between?(ImagemTileCutter::MIN_GRID_SIZE, ImagemTileCutter::MAX_GRID_SIZE)
  end

  def apply_cut_feedback_flash!
    feedback_key = params[:cut_feedback_key].to_s
    return if feedback_key.blank?

    feedback = ImagemCutProgressStore.read_feedback(imagem_id: @imagem.id, feedback_key: feedback_key)
    return if feedback.blank?

    feedback = feedback.with_indifferent_access

    message = feedback[:message].to_s
    level = feedback[:flash_level].to_s
    flash_type = %w[alert notice].include?(level) ? level.to_sym : :notice

    flash.now[flash_type] = message if message.present?
    ImagemCutProgressStore.delete_feedback(imagem_id: @imagem.id, feedback_key: feedback_key)
  end
end
