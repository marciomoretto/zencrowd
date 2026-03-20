require_dependency Rails.root.join('app/services/imagem_metadata_extractor').to_s
require_dependency Rails.root.join('app/services/imagem_tile_cutter').to_s

class ImagensController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_imagem, only: [:show, :update, :destroy, :cortar]
  before_action :load_eventos, only: [:show, :update]

  # GET /imagens
  def index
    @cidade_filter = cidade_filter_param
    @sort = sort_param
    @direction = direction_param
    @cidades = Imagem.where.not(cidade: [nil, '']).distinct.order(:cidade).pluck(:cidade)

    scope = Imagem.includes(:evento)
    scope = scope.where(cidade: @cidade_filter) if @cidade_filter.present?

    @imagens = scope.order(@sort => @direction)
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
  def show; end

  # PATCH /imagens/:id
  def update
    evento_id = evento_associacao_id

    if evento_id.present? && Evento.where(id: evento_id).none?
      flash.now[:alert] = 'Evento selecionado invalido.'
      return render :show, status: :unprocessable_entity
    end

    if @imagem.update(evento_id: evento_id.presence)
      redirect_to imagem_path(@imagem), notice: 'Evento da imagem atualizado com sucesso.'
    else
      flash.now[:alert] = @imagem.errors.full_messages.join(', ')
      render :show, status: :unprocessable_entity
    end
  end

  # POST /imagens/:id/cortar
  def cortar
    cutter = ::ImagemTileCutter.new(
      imagem: @imagem,
      uploader: current_user,
      rows: params[:rows],
      cols: params[:cols]
    )

    result = cutter.call(replace_existing: @imagem.tiles.exists?)

    if result.success?
      redirect_to imagem_path(@imagem), notice: "Imagem cortada com sucesso! #{result.created_count} tile(s) gerado(s)."
    else
      redirect_to imagem_path(@imagem), alert: result.error
    end
  end

  # DELETE /imagens/:id
  def destroy
    if @imagem.destroy
      redirect_to new_imagem_path, notice: 'Imagem removida com sucesso!'
    else
      errors = @imagem.errors.full_messages.presence || ['Nao foi possivel remover a imagem.']
      redirect_to imagem_path(@imagem), alert: errors.join(', ')
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
    params.fetch(:imagem, {}).permit(:evento_id, :evento_autocomplete)
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

  def cidade_filter_param
    cidade = params[:cidade].to_s.strip
    cidade.presence
  end

  def sort_param
    sort = params[:sort].to_s
    %w[id data_hora].include?(sort) ? sort : 'data_hora'
  end

  def direction_param
    params[:direction].to_s.downcase == 'asc' ? :asc : :desc
  end
end
