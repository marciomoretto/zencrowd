require_dependency Rails.root.join('app/services/imagem_metadata_extractor').to_s

class Admin::EventosController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_evento, only: [:show, :edit, :update, :destroy]

  def index
    @eventos = Evento.includes(:imagens).order(created_at: :desc)
  end

  def show
    @imagens = @evento.imagens.order(created_at: :desc)
  end

  def new
    @evento = Evento.new
  end

  def edit; end

  def create
    @evento = Evento.new(evento_core_params)
    uploaded_file = uploaded_imagem_file

    if create_evento_with_optional_imagem(uploaded_file)
      redirect_to admin_evento_path(@evento), notice: 'Evento criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    uploaded_file = uploaded_imagem_file

    if update_evento_with_optional_imagem(uploaded_file)
      redirect_to admin_evento_path(@evento), notice: 'Evento atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    nome = @evento.nome

    if @evento.destroy
      redirect_to admin_eventos_path, notice: "Evento #{nome} removido com sucesso."
    else
      errors = @evento.errors.full_messages.presence || ['Nao foi possivel remover o evento.']
      redirect_to admin_eventos_path, alert: errors.join(', ')
    end
  end

  private

  def set_evento
    @evento = Evento.find(params[:id])
  end

  def evento_params
    params.require(:evento).permit(:nome, :categoria, :arquivo)
  end

  def evento_core_params
    attrs = evento_params.except(:arquivo).to_h
    attrs['categoria'] = nil if attrs['categoria'].blank?
    attrs
  end

  def uploaded_imagem_file
    evento_params[:arquivo]
  end

  def create_evento_with_optional_imagem(uploaded_file)
    return @evento.save if uploaded_file.blank?

    created = false

    ActiveRecord::Base.transaction do
      @evento.save!

      unless create_imagem_for_evento(@evento, uploaded_file)
        raise ActiveRecord::Rollback
      end

      created = true
    end

    created
  rescue ActiveRecord::RecordInvalid
    false
  end

  def update_evento_with_optional_imagem(uploaded_file)
    return @evento.update(evento_core_params) if uploaded_file.blank?

    updated = false

    ActiveRecord::Base.transaction do
      unless @evento.update(evento_core_params)
        raise ActiveRecord::Rollback
      end

      unless create_imagem_for_evento(@evento, uploaded_file)
        raise ActiveRecord::Rollback
      end

      updated = true
    end

    updated
  end

  def create_imagem_for_evento(evento, uploaded_file)
    unless valid_image_upload?(uploaded_file)
      evento.errors.add(:base, 'Selecione um arquivo de imagem valido (JPG ou PNG).')
      return false
    end

    metadata = ::ImagemMetadataExtractor.extract(uploaded_file)

    imagem = Imagem.new(
      default_imagem_attributes
        .merge(metadata[:normalized] || {})
        .merge(
          evento: evento,
          exif_metadata: metadata[:exif] || {},
          xmp_metadata: metadata[:xmp] || {}
        )
    )

    imagem.arquivo.attach(uploaded_file)

    return true if imagem.save

    imagem.errors.full_messages.each do |message|
      evento.errors.add(:base, "Imagem: #{message}")
    end
    false
  end

  def valid_image_upload?(uploaded_file)
    return false unless uploaded_file.respond_to?(:content_type)

    %w[image/jpeg image/jpg image/png].include?(uploaded_file.content_type)
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
