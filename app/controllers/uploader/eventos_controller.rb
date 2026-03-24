require_dependency Rails.root.join('app/services/imagem_metadata_extractor').to_s

class Uploader::EventosController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_uploader!
  before_action :set_evento, only: [:show, :edit, :update, :destroy, :pasta, :mosaic, :render_mosaic, :mosaic_progress]
  before_action :load_pastas_disponiveis, only: [:new, :create, :edit, :update, :show]
  before_action :load_drone_options, only: [:show, :update]

  def index
    @cidade_filter = index_cidade_filter_param
    @categoria_filter = index_categoria_filter_param
    @sort = index_sort_param
    @direction = index_direction_param
    @cidades = Evento.where.not(cidade: [nil, '']).distinct.order(:cidade).pluck(:cidade)

    scope = Evento.includes(:imagens)
    scope = scope.where(cidade: @cidade_filter) if @cidade_filter.present?
    scope = apply_categoria_filter(scope)

    @eventos = paginate_scope(apply_index_sort(scope))
  end

  def show
    @pastas_sort = pastas_sort_param
    @pastas_direction = pastas_direction_param

    imagens_por_pasta_completas = @evento.imagens.includes(:tiles).to_a.group_by { |imagem| imagem.pasta.presence || 'Sem pasta' }

    pastas_resumo = imagens_por_pasta_completas.map do |pasta_nome, imagens|
      tiles_unicos = imagens.flat_map(&:tiles).uniq(&:id)
      quantidade_cabecas = tiles_unicos.sum { |tile| tile.head_count.to_i }

      {
        nome: pasta_nome,
        quantidade_imagens: imagens.size,
        quantidade_cabecas: quantidade_cabecas
      }
    end

    @pastas_resumo = sort_pastas_resumo(pastas_resumo)
    @pastas_paginadas = paginate_array_scope(@pastas_resumo)
  end

  def pasta
    @sort = imagens_sort_param
    @direction = imagens_direction_param
    @zenith_tolerance_degrees = AppSetting.zenith_tolerance_degrees

    @pasta_param = params[:pasta].to_s.strip
    @pasta_nome = @pasta_param.presence || 'Sem pasta'
    @latest_mosaic_preview_url = latest_mosaic_preview_url(@pasta_nome)

    scope = if @pasta_param.present?
              @evento.imagens.where(pasta: @pasta_param)
            else
              @evento.imagens.where(pasta: [nil, ''])
            end

    @imagens = paginate_scope(scope.order(@sort => @direction, id: @direction))
  end

  def mosaic
    @pasta_param = params[:pasta].to_s.strip
    @pasta_nome = @pasta_param.presence || 'Sem pasta'
    @progress_key = params[:key].to_s.strip
    @latest_mosaic_preview_url = latest_mosaic_preview_url(@pasta_nome)

    if @progress_key.present?
      @mosaic_status_url = mosaic_progress_uploader_evento_path(@evento, key: @progress_key, pasta: @pasta_param)
    end
  end

  def render_mosaic
    pasta_param = params[:pasta].to_s.strip
    progress_key = SecureRandom.uuid

    EventoMosaicProgressStore.write(
      evento_id: @evento.id,
      progress_key: progress_key,
      payload: {
        status: 'queued',
        progress: 0,
        stage: 'queued',
        message: 'Mosaico enfileirado para processamento...'
      }
    )

    RenderEventoMosaicJob.perform_later(@evento.id, pasta_param, progress_key)

    respond_to do |format|
      format.json do
        render json: {
          progress_key: progress_key,
          status_url: mosaic_progress_uploader_evento_path(@evento, key: progress_key, pasta: pasta_param),
          mosaic_url: mosaic_uploader_evento_path(@evento, key: progress_key, pasta: pasta_param)
        }, status: :accepted
      end

      format.html do
        redirect_to mosaic_uploader_evento_path(@evento, key: progress_key, pasta: pasta_param),
                    notice: 'Mosaico enfileirado. Acompanhe o progresso nesta pagina.'
      end
    end
  rescue StandardError => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
      format.html do
        redirect_to pasta_uploader_evento_path(@evento, pasta: pasta_param),
                    alert: "Falha ao gerar mosaico: #{e.message}"
      end
    end
  end

  def mosaic_progress
    progress_key = params[:key].to_s
    payload = EventoMosaicProgressStore.read(evento_id: @evento.id, progress_key: progress_key)

    if payload.blank?
      render json: { status: 'not_found', error: 'Progresso do mosaico não encontrado.' }, status: :not_found
      return
    end

    render json: payload, status: :ok
  end

  def new
    @evento = Evento.new
  end

  def edit; end

  def create
    @evento = Evento.new(evento_core_params)
    uploaded_files = uploaded_imagem_files
    pasta = selected_upload_pasta

    if uploaded_files.present? && pasta.blank?
      @evento.errors.add(:base, 'Informe uma pasta para as imagens enviadas.')
      return render :new, status: :unprocessable_entity
    end

    if create_evento_with_optional_imagens(uploaded_files, pasta: pasta)
      redirect_to uploader_evento_path(@evento), notice: 'Evento criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    uploaded_files = uploaded_imagem_files
    pasta = selected_upload_pasta
    redirect_to_pasta = params.key?(:redirect_to_pasta)

    if uploaded_files.present? && pasta.blank?
      @evento.errors.add(:base, 'Informe uma pasta para as imagens enviadas.')
      return respond_to do |format|
        format.html do
          if redirect_to_pasta
            redirect_to update_redirect_path, alert: @evento.errors.full_messages.join(', ')
          else
            render :show, status: :unprocessable_entity
          end
        end
        format.json { render json: { success: false, errors: @evento.errors.full_messages }, status: :unprocessable_entity }
      end
    end

    respond_to do |format|
      if update_evento_with_optional_imagens(uploaded_files, pasta: pasta)
        format.html { redirect_to update_redirect_path, notice: 'Evento atualizado com sucesso.' }
        format.json { render json: { success: true }, status: :ok }
      else
        format.html do
          if redirect_to_pasta
            redirect_to update_redirect_path, alert: (@evento.errors.full_messages.presence || ['Nao foi possivel atualizar o evento.']).join(', ')
          else
            render :edit, status: :unprocessable_entity
          end
        end
        format.json { render json: { success: false, errors: @evento.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    nome = @evento.nome

    if @evento.destroy
      redirect_to uploader_eventos_path, notice: "Evento #{nome} removido com sucesso."
    else
      errors = @evento.errors.full_messages.presence || ['Nao foi possivel remover o evento.']
      redirect_to uploader_eventos_path, alert: errors.join(', ')
    end
  end

  private

  def set_evento
    @evento = Evento.find(params[:id])
  end

  def evento_params
    params.require(:evento).permit(:nome, :categoria, :data, :cidade, :local, :drone_id)
  end

  def evento_core_params
    attrs = evento_params.except(:arquivo).to_h

    # Normaliza categoria vazia apenas quando o campo foi enviado.
    if attrs.key?('categoria')
      attrs['categoria'] = nil if attrs['categoria'].blank?
    end

    # Normaliza campos textuais opcionais apenas quando enviados.
    if attrs.key?('cidade')
      attrs['cidade'] = nil if attrs['cidade'].blank?
    end

    if attrs.key?('local')
      attrs['local'] = nil if attrs['local'].blank?
    end

    if attrs.key?('data')
      attrs['data'] = nil if attrs['data'].blank?
    end

    if attrs.key?('drone_id')
      attrs['drone_id'] = nil if attrs['drone_id'].blank?
    end

    attrs
  end

  def uploaded_imagem_files
    raw_files = params.fetch(:evento, {})[:arquivo]
    files = if raw_files.is_a?(ActionController::Parameters)
              raw_files.values
            else
              Array(raw_files)
            end

    files.compact_blank
  end

  def upload_pasta_params
    params.fetch(:evento, {}).permit(:pasta_existente, :nova_pasta)
  end

  def selected_upload_pasta
    new_pasta = upload_pasta_params[:nova_pasta].to_s.strip
    return new_pasta if new_pasta.present?

    upload_pasta_params[:pasta_existente].to_s.strip.presence
  end

  def load_pastas_disponiveis
    @pastas_disponiveis = Imagem.where.not(pasta: [nil, '']).distinct.order(:pasta).pluck(:pasta)
  end

  def load_drone_options
    @drone_options = Drone.order(:modelo, :lente).map { |drone| [drone.chave, drone.id] }
  end

  def create_evento_with_optional_imagens(uploaded_files, pasta: nil)
    return @evento.save if uploaded_files.blank?

    created = false

    ActiveRecord::Base.transaction do
      @evento.save!

      unless create_imagens_for_evento(@evento, uploaded_files, pasta: pasta)
        raise ActiveRecord::Rollback
      end

      created = true
    end

    created
  rescue ActiveRecord::RecordInvalid
    false
  end

  def update_evento_with_optional_imagens(uploaded_files, pasta: nil)
    return @evento.update(evento_core_params) if uploaded_files.blank?

    updated = false

    ActiveRecord::Base.transaction do
      unless @evento.update(evento_core_params)
        raise ActiveRecord::Rollback
      end

      unless create_imagens_for_evento(@evento, uploaded_files, pasta: pasta)
        raise ActiveRecord::Rollback
      end

      updated = true
    end

    updated
  end

  def create_imagens_for_evento(evento, uploaded_files, pasta: nil)
    uploaded_files.each do |uploaded_file|
      next if uploaded_file.blank?

      return false unless create_imagem_for_evento(evento, uploaded_file, pasta: pasta)
    end

    true
  end

  def create_imagem_for_evento(evento, uploaded_file, pasta: nil)
    unless valid_image_upload?(uploaded_file)
      evento.errors.add(:base, 'Selecione um arquivo de imagem valido (JPG ou PNG).')
      return false
    end

    metadata = ::ImagemMetadataExtractor.extract(uploaded_file)
    normalized_attrs = (metadata[:normalized] || {}).to_h.symbolize_keys
    metadata_date = extract_event_date_from_metadata(metadata)

    imagem_attrs = default_imagem_attributes.merge(normalized_attrs)
    imagem_attrs = fill_imagem_location_from_evento(evento, imagem_attrs)

    imagem = Imagem.new(
      imagem_attrs
        .merge(
          evento: evento,
          pasta: pasta,
          exif_metadata: metadata[:exif] || {},
          xmp_metadata: metadata[:xmp] || {}
        )
    )

    imagem.arquivo.attach(uploaded_file)

    unless imagem.save
      imagem.errors.full_messages.each do |message|
        evento.errors.add(:base, "Imagem: #{message}")
      end
      return false
    end

    unless sync_evento_from_imagem(evento, imagem, metadata_date: metadata_date)
      evento.errors.add(:base, 'Nao foi possivel atualizar dados do evento a partir da imagem.')
      return false
    end

    true

  end

  def latest_mosaic_preview_url(pasta_nome)
    mosaics_root = Rails.root.join('public', 'mosaics', "evento_#{@evento.id}", mosaic_safe_fragment(pasta_nome))
    return nil unless Dir.exist?(mosaics_root)

    pattern = File.join(mosaics_root.to_s, 'mosaic_*.{jpg,jpeg,png,webp,tif,tiff}')
    candidates = Dir.glob(pattern, File::FNM_CASEFOLD)
    return nil if candidates.empty?

    selected_path = candidates.max_by { |path| File.mtime(path) }
    public_root = Rails.root.join('public').to_s
    relative = selected_path.to_s.sub(%r{\A#{Regexp.escape(public_root)}/?}, '')

    "/#{relative}"
  rescue StandardError
    nil
  end

  def mosaic_safe_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end

  def fill_imagem_location_from_evento(evento, imagem_attrs)
    attrs = imagem_attrs.deep_dup

    if evento_location_blank_or_default?(attrs[:cidade], default_placeholder: 'nao informada')
      cidade_evento = syncable_location_value(evento.cidade, default_placeholder: 'nao informada')
      attrs[:cidade] = cidade_evento if cidade_evento.present?
    end

    if evento_location_blank_or_default?(attrs[:local], default_placeholder: 'nao informado')
      local_evento = syncable_location_value(evento.local, default_placeholder: 'nao informado')
      attrs[:local] = local_evento if local_evento.present?
    end

    attrs
  end

  def sync_evento_from_imagem(evento, imagem, metadata_date: nil)
    attrs = {}

    if evento_location_blank_or_default?(evento.cidade, default_placeholder: 'nao informada')
      cidade = syncable_location_value(imagem.cidade, default_placeholder: 'nao informada')
      attrs[:cidade] = cidade if cidade.present?
    end

    if evento_location_blank_or_default?(evento.local, default_placeholder: 'nao informado')
      local = syncable_location_value(imagem.local, default_placeholder: 'nao informado')
      attrs[:local] = local if local.present?
    end

    if evento.data.blank? && metadata_date.present?
      attrs[:data] = metadata_date
    end

    return true if attrs.empty?

    evento.update(attrs)
  end

  def extract_event_date_from_metadata(metadata)
    return nil unless metadata.is_a?(Hash)

    candidates = []
    collect_metadata_date_candidates(metadata[:exif] || metadata['exif'], candidates)
    collect_metadata_date_candidates(metadata[:xmp] || metadata['xmp'], candidates)

    candidates.each do |candidate|
      parsed = parse_metadata_datetime(candidate)
      return parsed.to_date if parsed
    end

    nil
  end

  def collect_metadata_date_candidates(value, result, current_key = nil)
    case value
    when Hash
      value.each do |key, inner_value|
        nested_key = current_key ? "#{current_key}.#{key}" : key.to_s
        collect_metadata_date_candidates(inner_value, result, nested_key)
      end
    when Array
      value.each { |item| collect_metadata_date_candidates(item, result, current_key) }
    else
      return if value.blank?
      return unless metadata_key_likely_date?(current_key)

      result << value
    end
  end

  def metadata_key_likely_date?(key)
    normalized_key = normalize_location(key)
    %w[datetime date time created digitized metadata].any? { |fragment| normalized_key.include?(fragment) }
  end

  def parse_metadata_datetime(value)
    case value
    when Time
      value
    when DateTime
      value.to_time
    when Date
      value.to_time
    else
      text = value.to_s.strip
      return nil if text.blank?

      if text.match?(/\A\d{4}:\d{2}:\d{2}\s+\d{2}:\d{2}:\d{2}\z/)
        Time.zone.strptime(text, '%Y:%m:%d %H:%M:%S')
      else
        Time.zone.parse(text)
      end
    end
  rescue StandardError
    nil
  end

  def evento_location_blank_or_default?(value, default_placeholder:)
    normalized = normalize_location(value)
    normalized.blank? || normalized == default_placeholder
  end

  def syncable_location_value(value, default_placeholder:)
    cleaned = value.to_s.strip
    normalized = normalize_location(cleaned)

    return nil if normalized.blank? || normalized == default_placeholder

    cleaned
  end

  def normalize_location(value)
    I18n.transliterate(value.to_s).strip.downcase
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

  def apply_categoria_filter(scope)
    return scope if @categoria_filter.blank?
    return scope.where(categoria: nil) if @categoria_filter == 'sem_categoria'

    categoria_enum = Evento.defined_enums.fetch('categoria', {})
    return scope.where(categoria: @categoria_filter) if categoria_enum.key?(@categoria_filter)

    scope
  end

  def apply_index_sort(scope)
    return scope.order(created_at: :desc) unless @sort == 'data'

    scope.order(data: @direction, id: @direction)
  end

  def index_cidade_filter_param
    params[:cidade].to_s.strip.presence
  end

  def index_categoria_filter_param
    params[:categoria].to_s.strip.presence
  end

  def index_sort_param
    sort = params[:sort].to_s
    sort == 'data' ? sort : 'data'
  end

  def index_direction_param
    params[:direction].to_s.downcase == 'asc' ? :asc : :desc
  end

  def imagens_sort_param
    sort = params[:sort].to_s
    %w[id data_hora].include?(sort) ? sort : 'data_hora'
  end

  def imagens_direction_param
    params[:direction].to_s.downcase == 'asc' ? :asc : :desc
  end

  def pastas_sort_param
    sort = params[:sort].to_s
    %w[nome quantidade_imagens quantidade_cabecas].include?(sort) ? sort : 'nome'
  end

  def pastas_direction_param
    direction = params[:direction].to_s.downcase
    return direction.to_sym if %w[asc desc].include?(direction)

    @pastas_sort == 'nome' ? :asc : :desc
  end

  def sort_pastas_resumo(pastas_resumo)
    sorted = case @pastas_sort
             when 'quantidade_imagens'
               pastas_resumo.sort_by { |item| [item[:quantidade_imagens], item[:nome]] }
             when 'quantidade_cabecas'
               pastas_resumo.sort_by { |item| [item[:quantidade_cabecas], item[:nome]] }
             else
               pastas_resumo.sort_by { |item| item[:nome].to_s.downcase }
             end

    @pastas_direction == :desc ? sorted.reverse : sorted
  end

  def update_redirect_path
    return uploader_evento_path(@evento) unless params.key?(:redirect_to_pasta)

    pasta_param = params[:redirect_to_pasta].to_s
    pasta_param = '' if pasta_param == '__sem_pasta__'

    pasta_uploader_evento_path(@evento, pasta: pasta_param)
  end

end
