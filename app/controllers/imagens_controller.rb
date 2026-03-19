class ImagensController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_imagem, only: [:show]
  before_action :load_tiles, only: [:new, :create]

  # GET /imagens/new
  def new
    @imagem = Imagem.new(data_hora: Time.current.change(sec: 0))
  end

  # POST /imagens
  def create
    attrs = imagem_params
    tile_ids = normalize_tile_ids(attrs.delete(:tile_ids))

    @imagem = Imagem.new(attrs)
    @imagem.tile_ids = tile_ids if tile_ids.present?

    if @imagem.save
      redirect_to imagem_path(@imagem), notice: 'Imagem enviada com sucesso!'
    else
      flash.now[:alert] = @imagem.errors.full_messages.join(', ')
      render :new, status: :unprocessable_entity
    end
  rescue ActionController::ParameterMissing
    @imagem = Imagem.new
    flash.now[:alert] = 'Preencha os dados obrigatorios da imagem.'
    render :new, status: :unprocessable_entity
  end

  # GET /imagens/:id
  def show; end

  private

  def set_imagem
    @imagem = Imagem.includes(:tiles).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = 'Imagem nao encontrada.'
    redirect_to new_imagem_path
  end

  def load_tiles
    @tiles = Tile.order(created_at: :desc)
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
end
