class ImagesController < ApplicationController
  MAX_P2PNET_PIXELS = 12_000_000
  OOM_TILE_UPLOAD_ALERT = 'Imagem muito grande, tente quebrar em pedaços menores.'

  before_action :authenticate_user!
  before_action :authorize_admin!, only: [:index, :create, :update, :destroy, :mark_paid, :expire_reservation, :new, :count_heads]
  before_action :authorize_annotator_or_admin!, only: [:show, :preview]
  before_action :authorize_annotator!, only: [:reserve, :give_up, :submit, :zen_plot_points, :finalize_zen_plot_points]
  before_action :expire_stale_reservations!, only: [:reserve, :give_up, :submit, :zen_plot_points, :finalize_zen_plot_points]
  before_action :authorize_reviewer!, only: [:start_review, :approve, :reject]
  before_action :set_image, only: [:show, :preview, :update, :destroy, :reserve, :give_up, :submit, :zen_plot_points, :finalize_zen_plot_points, :start_review, :approve, :reject, :mark_paid, :expire_reservation, :count_heads]

  # GET /tiles
  # Lista todos os tiles cadastrados no sistema
  def index
    @status_filter = status_filter_param
    @reserver_filter = reserver_filter_param
    @sort = sort_param
    @direction = direction_param

    @reserver_options = User.where(id: Tile.where.not(reserver_id: nil).select(:reserver_id)).order(:name)

    scope = Tile.includes(:uploader, :reserver, imagens: [arquivo_attachment: :blob])
    scope = scope.where(status: @status_filter) if @status_filter.present?
    scope = scope.where(reserver_id: @reserver_filter) if @reserver_filter.present?

    @tiles = apply_sort(scope)

    respond_to do |format|
      format.html # renderiza app/views/images/index.html.erb
      format.json { render json: @tiles.map { |tile| tile_json(tile) } }
    end
  end

  # GET /tiles/:id
  # Exibe o tile e seus metadados
  def show
    @latest_annotation = @image.annotations.includes(:user, review: :reviewer).order(created_at: :desc).first
    @latest_review = @latest_annotation&.review
    @preview_available = image_file_path(@image).present?

    respond_to do |format|
      format.html
      format.json { render json: tile_json(@image) }
    end
  end

  # POST /tiles/:id/count_heads
  # Executa contagem de cabecas sob demanda pelo show
  def count_heads
    count_result = assign_head_count_to_tile(@image, expose_error: true)
    @image.reload

    if count_result[:status] == :ok && @image.head_count.present?
      flash[:notice] = "Contagem concluída: #{@image.head_count} cabeças estimadas."
    elsif count_result[:status] == :warning
      flash[:alert] = count_result[:message]
    else
      flash[:alert] = count_result[:message].presence || 'Não foi possível calcular a contagem de cabeças para este tile.'
    end

    redirect_to tile_path(@image)
  end

  # PATCH /tiles/:id
  # Atualiza apenas o valor da tarefa (admin)
  def update
    respond_to do |format|
      if @image.update(image_update_params)
        format.html do
          flash[:notice] = 'Tile atualizado com sucesso.'
          redirect_to tile_path(@image)
        end
        format.json { render json: tile_json(@image), status: :ok }
      else
        format.html do
          flash[:alert] = @image.errors.full_messages.join(', ')
          redirect_to tile_path(@image)
        end
        format.json { render json: { errors: @image.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /tiles/:id
  # Remove o tile do banco de dados (admin)
  def destroy
    respond_to do |format|
      if @image.destroy
        format.html do
          flash[:notice] = 'Tile removido com sucesso.'
          redirect_to tiles_path
        end
        format.json { head :no_content }
      else
        errors = @image.errors.full_messages.presence || ['Não foi possível remover o tile.']

        format.html do
          flash[:alert] = errors.join(', ')
          redirect_to tile_path(@image)
        end
        format.json { render json: { errors: errors }, status: :unprocessable_entity }
      end
    end
  end

  # GET /tiles/:id/preview
  # Retorna o arquivo do tile para visualizacao inline
  def preview
    file_path = image_file_path(@image)
    return head :not_found unless file_path

    send_file file_path,
              type: Marcel::MimeType.for(Pathname.new(file_path), name: @image.original_filename),
              disposition: 'inline'
  end

  # GET /tiles/new
  def new
    # Apenas renderiza o formulário
  end

  # POST /tiles
  # Faz upload de um novo tile
  def create
    uploaded_file = params[:file]

    respond_to do |format|
      # HTML (formulário)
      format.html do
        # Validar presença do arquivo
        if uploaded_file.blank?
          flash[:alert] = 'Nenhum arquivo foi enviado'
          return redirect_to new_tile_path
        end

        unless valid_image_type?(uploaded_file)
          flash[:alert] = 'Formato de arquivo não suportado. Use JPG, JPEG ou PNG'
          return redirect_to new_tile_path
        end

        if uploaded_file.size > 10.megabytes
          flash[:alert] = 'Arquivo muito grande. Tamanho máximo: 10MB'
          return redirect_to new_tile_path
        end

        tile = Tile.new(
          original_filename: uploaded_file.original_filename,
          storage_path: '',
          status: :available,
          uploader: current_user
        )

        begin
          storage_path = save_uploaded_file(uploaded_file)
          tile.storage_path = storage_path

          if tile.save
            count_result = assign_head_count_to_tile(tile, expose_error: true)
            flash[:notice] = 'Tile enviado com sucesso!'
            if count_result[:status] != :ok && count_result[:message].present?
              flash[:alert] = count_result[:message]
            end
            redirect_to tile_path(tile)
          else
            File.delete(Rails.root.join(storage_path)) if File.exist?(Rails.root.join(storage_path))
            flash[:alert] = tile.errors.full_messages.join(', ')
            redirect_to new_tile_path
          end
        rescue StandardError => e
          File.delete(Rails.root.join(storage_path)) if storage_path && File.exist?(Rails.root.join(storage_path))
          flash[:alert] = "Erro ao fazer upload: #{e.message}"
          redirect_to new_tile_path
        end
      end

      # JSON (API)
      format.json do
        if uploaded_file.blank?
          return render json: { error: 'Nenhum arquivo foi enviado' }, status: :unprocessable_entity
        end

        unless valid_image_type?(uploaded_file)
          return render json: { error: 'Formato de arquivo não suportado. Use JPG, JPEG ou PNG' }, status: :unprocessable_entity
        end

        if uploaded_file.size > 10.megabytes
          return render json: { error: 'Arquivo muito grande. Tamanho máximo: 10MB' }, status: :unprocessable_entity
        end

        tile = Tile.new(
          original_filename: uploaded_file.original_filename,
          storage_path: '',
          status: :available,
          uploader: current_user
        )

        begin
          storage_path = save_uploaded_file(uploaded_file)
          tile.storage_path = storage_path

          if tile.save
            count_result = assign_head_count_to_tile(tile, expose_error: true)
            payload = tile_json(tile)
            if count_result[:status] == :warning
              payload[:warning] = count_result[:message]
            elsif count_result[:status] == :error
              payload[:error] = count_result[:message]
            end
            render json: payload, status: :created
          else
            File.delete(Rails.root.join(storage_path)) if File.exist?(Rails.root.join(storage_path))
            render json: { errors: tile.errors.full_messages }, status: :unprocessable_entity
          end
        rescue StandardError => e
          File.delete(Rails.root.join(storage_path)) if storage_path && File.exist?(Rails.root.join(storage_path))
          render json: { error: "Erro ao fazer upload: #{e.message}" }, status: :internal_server_error
        end
      end
    end
  end

  # POST /tiles/:id/reserve
  # Annotator reserves an available tile
  def reserve
    begin
      @image.reserve!(current_user)
      respond_to do |format|
        format.html do
          expiration_hours = Image.reservation_expiration_hours
          hour_label = expiration_hours == 1 ? 'hora' : 'horas'
          flash[:notice] = 'Tile reservado com sucesso!'
          flash[:warning] = "Tarefas ociosas por #{expiration_hours} #{hour_label} voltam a ficar disponíveis."
          redirect_to my_task_path
        end
        format.json { render json: tile_json(@image), status: :ok }
      end
    rescue Tile::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to available_tiles_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  # POST /tiles/:id/give_up
  # Annotator gives up a reserved tile, returning it to available.
  def give_up
    begin
      @image.give_up!(current_user)

      respond_to do |format|
        format.html do
          flash[:notice] = 'Você desistiu da tarefa. O tile voltou para disponível.'
          redirect_to available_tiles_path
        end
        format.json { render json: tile_json(@image), status: :ok }
      end
    rescue Tile::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to my_task_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  # POST /tiles/:id/submit
  # Annotator submits annotation for reserved tile
  def submit
    begin
      respond_to do |format|
        format.html do
          @image.submit!(current_user, params[:projeto_tar], params[:dados_csv], params[:config_json], params[:zen_plot_points_json])
          flash[:notice] = 'Tile submetido com sucesso!'
          redirect_to my_task_path
        end
        format.json do
          @image.submit!(current_user, params[:projeto_tar], params[:dados_csv], params[:config_json], params[:zen_plot_points_json])
          render json: tile_json(@image), status: :ok
        end
      end
    rescue Tile::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to my_task_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  # GET|POST /tiles/:id/zen_plot_points
  # Loads persisted ZenPlot points for the tile and stores submit actions.
  def zen_plot_points
    return unless ensure_zen_plot_points_permission!

    if request.get?
      return render json: zen_plot_points_payload(@image), status: :ok
    end

    point_set, created = upsert_zen_plot_points!(@image, zen_plot_points_params, mark_as_finalized: false)
    warning_message = nil

    if @image.reserved?
      @image.refresh_reservation_expiration!(current_user)
      expiration_hours = Image.reservation_expiration_hours
      hour_label = expiration_hours == 1 ? 'hora' : 'horas'
      warning_message = "Tempo de expiração da tarefa foi atualizado para #{expiration_hours} #{hour_label} a partir de agora."
    end

    render json: zen_plot_points_response(
      point_set,
      warning: warning_message,
      reservation_expires_at: @image.reservation_expires_at
    ), status: (created ? :created : :ok)
  rescue TilePointSet::PayloadError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /tiles/:id/finalize_zen_plot_points
  # Persists current points and marks the point set as finalized.
  def finalize_zen_plot_points
    return unless ensure_zen_plot_points_permission!

    point_set = nil
    created = false

    ActiveRecord::Base.transaction do
      point_set, created = upsert_zen_plot_points!(@image, zen_plot_points_params, mark_as_finalized: true)

      if @image.reserved?
        @image.submit_with_zen_plot_points!(current_user, { points: point_set.points })
      end
    end

    render json: zen_plot_points_response(point_set), status: (created ? :created : :ok)
  rescue TilePointSet::PayloadError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue Tile::StateMachineError => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  end

  # POST /tiles/:id/start_review
  # Reviewer starts reviewing a submitted annotation
  def start_review
    begin
      respond_to do |format|
        format.html do
          @image.start_review!(current_user)
          Rails.logger.info "DEBUG: Após start_review! status do tile: #{@image.reload.status}"
          flash[:notice] = "Revisão iniciada com sucesso! (status: #{@image.status})"
          redirect_to reviewer_reviews_path
        end
        format.json do
          @image.start_review!(current_user)
          Rails.logger.info "DEBUG: Após start_review! status do tile: #{@image.reload.status}"
          render json: tile_json(@image), status: :ok
        end
      end
    rescue Tile::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to reviewer_reviews_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  # POST /tiles/:id/approve
  # Reviewer approves annotation in review
  def approve
    begin
      puts "DEBUG: Entrou no approve controller para tile ##{@image.id} (status: #{@image.status})"
      respond_to do |format|
        format.html do
          @image.approve!(current_user)
          @image.reload
          puts "DEBUG: Após approve! status do tile: #{@image.status}"
          flash[:notice] = 'Tile aprovado com sucesso!'
          redirect_to reviewer_reviews_path
        end
        format.json do
          @image.approve!(current_user)
          render json: tile_json(@image), status: :ok
        end
      end
    rescue Tile::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to reviewer_reviews_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end


  # POST /tiles/:id/reject
  # Reviewer rejects annotation in review

  def reject
    Rails.logger.info "DEBUG: INÍCIO DA ACTION REJECT - params: #{params.inspect}, current_user: #{current_user&.id}, tile_id: #{@image&.id}, status: #{@image&.status}"
    puts "DEBUG: INÍCIO DA ACTION REJECT - params: #{params.inspect}, current_user: #{current_user&.id}, tile_id: #{@image&.id}, status: #{@image&.status}"
    begin
      respond_to do |format|
        format.html do
          @image.reject!(current_user)
          Rails.logger.info "DEBUG: Após reject! status do tile: #{@image.reload.status}"
          flash[:notice] = "Tile devolvido para anotação. (status: #{@image.status})"
          redirect_to reviewer_reviews_path
        end
        format.json do
          @image.reject!(current_user)
          Rails.logger.info "DEBUG: Após reject! status do tile: #{@image.reload.status}"
          render json: tile_json(@image), status: :ok
        end
      end
    rescue Tile::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to reviewer_reviews_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end


  # POST /tiles/:id/mark_paid
  # Admin marks approved annotation as paid
  def mark_paid
    begin
      respond_to do |format|
        format.html do
          @image.mark_as_paid!(current_user)
          flash[:notice] = 'Tile marcado como pago.'
          redirect_to tiles_path
        end
        format.json do
          @image.mark_as_paid!(current_user)
          render json: tile_json(@image), status: :ok
        end
      end
    rescue Tile::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to tiles_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end



  # POST /tiles/:id/expire_reservation
  # Admin manually expires a reservation
  def expire_reservation
    begin
      respond_to do |format|
        format.html do
          @image.expire_reservation!
          flash[:notice] = 'Reserva expirada.'
          redirect_to tiles_path
        end
        format.json do
          @image.expire_reservation!
          render json: tile_json(@image), status: :ok
        end
      end
    rescue Tile::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to tiles_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  private

  def expire_stale_reservations!
    Tile.expire_all_reservations!
  end

  def set_image
    @image = Tile.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html do
        flash[:alert] = 'Tile não encontrado'
        fallback_path = current_user&.admin? ? tiles_path : dashboard_path
        redirect_back fallback_location: fallback_path
      end
      format.json { render json: { error: 'Tile not found' }, status: :not_found }
      format.any { head :not_found }
    end
  end

  def zen_plot_points_params
    params.permit(:axis, points: [:id, :x, :y]).to_h.symbolize_keys
  end

  def ensure_zen_plot_points_permission!
    return true if @image.reserver_id == current_user.id

    render json: { error: 'Permissão negada para acessar os pontos deste tile' }, status: :forbidden
    false
  end

  def upsert_zen_plot_points!(tile, raw_payload, mark_as_finalized: false)
    normalized_payload = TilePointSet.normalize_payload(raw_payload)
    point_set = tile.tile_point_set || tile.build_tile_point_set
    created = point_set.new_record?

    point_set.assign_attributes(
      axis: normalized_payload[:axis],
      points: normalized_payload[:points]
    )
    point_set.finalized_at = Time.current if mark_as_finalized
    point_set.save!

    [point_set, created]
  end

  def zen_plot_points_payload(tile)
    point_set = tile.tile_point_set
    return { axis: 'image', points: [] } unless point_set

    point_set.as_zen_plot_payload
  end

  def zen_plot_points_response(point_set, warning: nil, reservation_expires_at: nil)
    payload = point_set.as_zen_plot_payload

    payload.merge(
      id: point_set.id,
      tile_id: point_set.tile_id,
      points_count: payload[:points].size,
      finalized: point_set.finalized?,
      finalized_at: point_set.finalized_at,
      updated_at: point_set.updated_at,
      reservation_expires_at: reservation_expires_at,
      warning: warning
    )
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

  def image_update_params
    params.permit(image: [:task_value], tile: [:task_value])[:tile] || params.require(:image).permit(:task_value)
  end

  # Valida se o tipo do arquivo é um tile suportado
  def valid_image_type?(file)
    return false unless file.respond_to?(:content_type)
    
    allowed_types = ['image/jpeg', 'image/jpg', 'image/png']
    allowed_types.include?(file.content_type.downcase)
  end

  # Salva o arquivo no sistema de arquivos e retorna o caminho
  def save_uploaded_file(file)
    # Criar diretório se não existir
    upload_dir = Rails.root.join('storage', 'uploads', 'images')
    FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)

    # Gerar nome único para o arquivo
    timestamp = Time.current.strftime('%Y%m%d%H%M%S')
    random_token = SecureRandom.hex(8)
    extension = File.extname(file.original_filename)
    filename = "#{timestamp}_#{random_token}#{extension}"

    # Caminho completo
    file_path = upload_dir.join(filename)

    # Salvar arquivo
    File.open(file_path, 'wb') do |f|
      f.write(file.read)
    end

    # Retornar caminho relativo a partir do Rails.root
    "storage/uploads/images/#{filename}"
  end

  # Serializa o tile para JSON
  def tile_json(tile)
    {
      id: tile.id,
      original_filename: tile.original_filename,
      storage_path: tile.storage_path,
      status: tile.status,
      head_count: tile.head_count,
      task_value: tile.task_value&.to_f,
      uploader: {
        id: tile.uploader.id,
        name: tile.uploader.name,
        email: tile.uploader.email
      },
      reserver: tile.reserver ? {
        id: tile.reserver.id,
        name: tile.reserver.name,
        email: tile.reserver.email
      } : nil,
      reserved_at: tile.reserved_at,
      reservation_expires_at: tile.reservation_expires_at,
      created_at: tile.created_at,
      updated_at: tile.updated_at
    }
  end

  def assign_head_count_to_tile(tile, expose_error: false)
    library_error_message = ensure_p2pnet_library_loaded
    if library_error_message.present?
      Rails.logger.warn("P2PNet unavailable for tile ##{tile.id}: #{library_error_message}")

      return {
        status: :error,
        message: (expose_error ? library_error_message : nil)
      }
    end

    image_path = image_file_path(tile)
    if image_path.blank?
      return {
        status: :error,
        message: (expose_error ? 'Arquivo do tile não foi encontrado para contagem.' : nil)
      }
    end

    return { status: :warning, message: OOM_TILE_UPLOAD_ALERT } if image_too_large_for_p2pnet?(image_path)

    output_path = p2pnet_output_path_for(tile)

    result = CrowdCountingP2PNet.annotate(
      image_path: image_path,
      output_path: output_path.to_s,
      threshold: 0.5,
      device: ENV.fetch('P2PNET_DEVICE', 'cpu')
    )

    tile.update_columns(
      head_count: result.count,
      task_value: task_value_from_head_count(result.count)
    )
    { status: :ok, count: result.count }
  rescue CrowdCountingP2PNet::InferenceError => e
    return { status: :warning, message: OOM_TILE_UPLOAD_ALERT } if oom_like_error?(e)

    summarized_error = compact_error_message(e)
    Rails.logger.warn("P2PNet inference failed for tile ##{tile.id}: #{summarized_error} | raw=#{e.message.to_s.lines.first.to_s.strip}")

    {
      status: :error,
      message: (expose_error ? "Falha na inferência: #{summarized_error}" : nil)
    }
  rescue StandardError => e
    summarized_error = compact_error_message(e)
    Rails.logger.warn("P2PNet head count unavailable for tile ##{tile.id}: #{e.class} - #{summarized_error}")

    {
      status: :error,
      message: (expose_error ? "Erro interno ao contar cabeças: #{summarized_error}" : nil)
    }
  ensure
    File.delete(output_path) if output_path && File.exist?(output_path)
  end

  def compact_error_message(error)
    lines = error.message.to_s.lines.map(&:strip).reject(&:blank?)
    candidate = lines.find do |line|
      !(line.downcase.start_with?('traceback') || line.downcase.start_with?('file "'))
    end

    (candidate.presence || error.class.to_s).truncate(180)
  end

  def ensure_p2pnet_library_loaded
    return nil if defined?(CrowdCountingP2PNet)

    require 'crowd_counting_p2pnet'
    return nil if defined?(CrowdCountingP2PNet)

    'Biblioteca de contagem indisponível no servidor. Reinicie a aplicação.'
  rescue LoadError => e
    details = compact_error_message(e)
    "Biblioteca de contagem indisponível no servidor (#{details}). Rode bundle install e reinicie o servidor."
  rescue StandardError => e
    details = compact_error_message(e)
    "Biblioteca de contagem indisponível no servidor (#{details})."
  end

  def p2pnet_output_path_for(tile)
    output_dir = Rails.root.join('tmp', 'p2pnet_tiles')
    FileUtils.mkdir_p(output_dir)
    output_dir.join("tile-#{tile.id}-#{SecureRandom.hex(6)}.jpg")
  end

  def image_too_large_for_p2pnet?(file_path)
    image = Vips::Image.new_from_file(file_path, access: :sequential)
    (image.width * image.height) > MAX_P2PNET_PIXELS
  rescue StandardError
    false
  end

  def oom_like_error?(error)
    message = error.message.to_s.downcase

    message.include?('oom') ||
      message.include?('out of memory') ||
      message.include?('cannot allocate memory') ||
      message.include?('killed') ||
      message.include?('exit 137') ||
      message.include?('137')
  end

  def image_json(image)
    tile_json(image)
  end

  def task_value_from_head_count(head_count)
    AppSetting.task_value_for_estimated_heads(head_count)
  rescue StandardError
    nil
  end

  def status_filter_param
    status = params[:status].to_s
    Tile.statuses.key?(status) ? status : nil
  end

  def reserver_filter_param
    value = params[:reserver_id].to_s
    return nil if value.blank?

    Integer(value)
  rescue ArgumentError
    nil
  end

  def sort_param
    sort = params[:sort].to_s
    %w[id task_value created_at].include?(sort) ? sort : 'created_at'
  end

  def direction_param
    params[:direction].to_s.downcase == 'asc' ? 'asc' : 'desc'
  end

  def apply_sort(scope)
    if @sort == 'task_value'
      scope.order(Arel.sql("task_value IS NULL, task_value #{@direction}"))
    else
      scope.order(@sort => @direction)
    end
  end
end
