class ImagensController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_imagem, only: [:show, :destroy]

  # GET /imagens/new
  def new
    @imagem = Imagem.new
  end

  # POST /imagens
  def create
    attrs = imagem_params.to_h.symbolize_keys.compact_blank
    tile_ids = normalize_tile_ids(attrs.delete(:tile_ids))

    @imagem = Imagem.new(default_imagem_attributes.merge(attrs))
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
end
