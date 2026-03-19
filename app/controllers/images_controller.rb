class ImagesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!, only: [:index, :create, :update, :destroy, :mark_paid, :expire_reservation, :new, :show, :preview]
  before_action :authorize_annotator!, only: [:reserve, :submit]
  before_action :authorize_reviewer!, only: [:start_review, :approve, :reject]
  before_action :set_image, only: [:show, :preview, :update, :destroy, :reserve, :submit, :start_review, :approve, :reject, :mark_paid, :expire_reservation]

  # GET /images
  # Lista todas as imagens cadastradas no sistema
  def index
    @images = Image.includes(:uploader, :reserver).order(created_at: :desc)
    respond_to do |format|
      format.html # renderiza app/views/images/index.html.erb
      format.json { render json: @images.map { |image| image_json(image) } }
    end
  end

  # GET /images/:id
  # Exibe a imagem e seus metadados
  def show
    @latest_annotation = @image.annotations.includes(:user, review: :reviewer).order(created_at: :desc).first
    @latest_review = @latest_annotation&.review
    @preview_available = image_file_path(@image).present?

    respond_to do |format|
      format.html
      format.json { render json: image_json(@image) }
    end
  end

  # PATCH /images/:id
  # Atualiza apenas o valor da tarefa (admin)
  def update
    respond_to do |format|
      if @image.update(image_update_params)
        format.html do
          flash[:notice] = 'Imagem atualizada com sucesso.'
          redirect_to image_path(@image)
        end
        format.json { render json: image_json(@image), status: :ok }
      else
        format.html do
          flash[:alert] = @image.errors.full_messages.join(', ')
          redirect_to image_path(@image)
        end
        format.json { render json: { errors: @image.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /images/:id
  # Remove a imagem do banco de dados (admin)
  def destroy
    respond_to do |format|
      if @image.destroy
        format.html do
          flash[:notice] = 'Imagem removida com sucesso.'
          redirect_to images_path
        end
        format.json { head :no_content }
      else
        errors = @image.errors.full_messages.presence || ['Não foi possível remover a imagem.']

        format.html do
          flash[:alert] = errors.join(', ')
          redirect_to image_path(@image)
        end
        format.json { render json: { errors: errors }, status: :unprocessable_entity }
      end
    end
  end

  # GET /images/:id/preview
  # Retorna o arquivo da imagem para visualizacao inline
  def preview
    file_path = image_file_path(@image)
    return head :not_found unless file_path

    send_file file_path,
              type: Marcel::MimeType.for(Pathname.new(file_path), name: @image.original_filename),
              disposition: 'inline'
  end

  # GET /images/new
  def new
    # Apenas renderiza o formulário
  end

  # POST /images
  # Faz upload de uma nova imagem
  def create
    uploaded_file = params[:file]
    task_value = params[:task_value]

    respond_to do |format|
      # HTML (formulário)
      format.html do
        # Validar presença do arquivo
        if uploaded_file.blank?
          flash[:alert] = 'Nenhum arquivo foi enviado'
          return redirect_to new_image_path
        end

        unless valid_image_type?(uploaded_file)
          flash[:alert] = 'Formato de arquivo não suportado. Use JPG, JPEG ou PNG'
          return redirect_to new_image_path
        end

        if uploaded_file.size > 10.megabytes
          flash[:alert] = 'Arquivo muito grande. Tamanho máximo: 10MB'
          return redirect_to new_image_path
        end

        image = Image.new(
          original_filename: uploaded_file.original_filename,
          storage_path: '',
          status: :available,
          task_value: task_value,
          uploader: current_user
        )

        begin
          storage_path = save_uploaded_file(uploaded_file)
          image.storage_path = storage_path

          if image.save
            flash[:notice] = 'Imagem enviada com sucesso!'
            redirect_to images_path
          else
            File.delete(Rails.root.join(storage_path)) if File.exist?(Rails.root.join(storage_path))
            flash[:alert] = image.errors.full_messages.join(', ')
            redirect_to new_image_path
          end
        rescue StandardError => e
          File.delete(Rails.root.join(storage_path)) if storage_path && File.exist?(Rails.root.join(storage_path))
          flash[:alert] = "Erro ao fazer upload: #{e.message}"
          redirect_to new_image_path
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

        image = Image.new(
          original_filename: uploaded_file.original_filename,
          storage_path: '',
          status: :available,
          task_value: task_value,
          uploader: current_user
        )

        begin
          storage_path = save_uploaded_file(uploaded_file)
          image.storage_path = storage_path

          if image.save
            render json: image_json(image), status: :created
          else
            File.delete(Rails.root.join(storage_path)) if File.exist?(Rails.root.join(storage_path))
            render json: { errors: image.errors.full_messages }, status: :unprocessable_entity
          end
        rescue StandardError => e
          File.delete(Rails.root.join(storage_path)) if storage_path && File.exist?(Rails.root.join(storage_path))
          render json: { error: "Erro ao fazer upload: #{e.message}" }, status: :internal_server_error
        end
      end
    end
  end

  # POST /images/:id/reserve
  # Annotator reserves an available image
  def reserve
    begin
      @image.reserve!(current_user)
      respond_to do |format|
        format.html do
          flash[:notice] = 'Imagem reservada com sucesso!'
          redirect_to my_task_path
        end
        format.json { render json: image_json(@image), status: :ok }
      end
    rescue Image::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to available_images_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  # POST /images/:id/submit
  # Annotator submits annotation for reserved image
  def submit
    begin
      respond_to do |format|
        format.html do
          @image.submit!(current_user, params[:projeto_tar], params[:dados_csv], params[:config_json])
          flash[:notice] = 'Imagem submetida com sucesso!'
          redirect_to my_task_path
        end
        format.json do
          @image.submit!(current_user, params[:projeto_tar], params[:dados_csv], params[:config_json])
          render json: image_json(@image), status: :ok
        end
      end
    rescue Image::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to my_task_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  # POST /images/:id/start_review
  # Reviewer starts reviewing a submitted annotation
  def start_review
    begin
      respond_to do |format|
        format.html do
          @image.start_review!(current_user)
          Rails.logger.info "DEBUG: Após start_review! status da imagem: #{@image.reload.status}"
          flash[:notice] = "Revisão iniciada com sucesso! (status: #{@image.status})"
          redirect_to reviewer_reviews_path
        end
        format.json do
          @image.start_review!(current_user)
          Rails.logger.info "DEBUG: Após start_review! status da imagem: #{@image.reload.status}"
          render json: image_json(@image), status: :ok
        end
      end
    rescue Image::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to reviewer_reviews_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  # POST /images/:id/approve
  # Reviewer approves annotation in review
  def approve
    begin
      puts "DEBUG: Entrou no approve controller para imagem ##{@image.id} (status: #{@image.status})"
      respond_to do |format|
        format.html do
          @image.approve!(current_user)
          @image.reload
          puts "DEBUG: Após approve! status da imagem: #{@image.status}"
          flash[:notice] = 'Imagem aprovada com sucesso!'
          redirect_to reviewer_reviews_path
        end
        format.json do
          @image.approve!(current_user)
          render json: image_json(@image), status: :ok
        end
      end
    rescue Image::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to reviewer_reviews_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end


  # POST /images/:id/reject
  # Reviewer rejects annotation in review

  def reject
    Rails.logger.info "DEBUG: INÍCIO DA ACTION REJECT - params: #{params.inspect}, current_user: #{current_user&.id}, image_id: #{@image&.id}, status: #{@image&.status}"
    puts "DEBUG: INÍCIO DA ACTION REJECT - params: #{params.inspect}, current_user: #{current_user&.id}, image_id: #{@image&.id}, status: #{@image&.status}"
    begin
      respond_to do |format|
        format.html do
          @image.reject!(current_user)
          Rails.logger.info "DEBUG: Após reject! status da imagem: #{@image.reload.status}"
          flash[:notice] = "Imagem devolvida para anotação. (status: #{@image.status})"
          redirect_to reviewer_reviews_path
        end
        format.json do
          @image.reject!(current_user)
          Rails.logger.info "DEBUG: Após reject! status da imagem: #{@image.reload.status}"
          render json: image_json(@image), status: :ok
        end
      end
    rescue Image::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to reviewer_reviews_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end


  # POST /images/:id/mark_paid
  # Admin marks approved annotation as paid
  def mark_paid
    begin
      respond_to do |format|
        format.html do
          @image.mark_as_paid!(current_user)
          flash[:notice] = 'Imagem marcada como paga.'
          redirect_to images_path
        end
        format.json do
          @image.mark_as_paid!(current_user)
          render json: image_json(@image), status: :ok
        end
      end
    rescue Image::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to images_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end



  # POST /images/:id/expire_reservation
  # Admin manually expires a reservation
  def expire_reservation
    begin
      respond_to do |format|
        format.html do
          @image.expire_reservation!
          flash[:notice] = 'Reserva expirada.'
          redirect_to images_path
        end
        format.json do
          @image.expire_reservation!
          render json: image_json(@image), status: :ok
        end
      end
    rescue Image::StateMachineError => e
      respond_to do |format|
        format.html do
          flash[:alert] = e.message
          redirect_to images_path
        end
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_image
    @image = Image.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html do
        flash[:alert] = 'Imagem não encontrada'
        fallback_path = current_user&.admin? ? images_path : dashboard_path
        redirect_back fallback_location: fallback_path
      end
      format.json { render json: { error: 'Image not found' }, status: :not_found }
      format.any { head :not_found }
    end
  end

  # Resolve com seguranca o caminho do arquivo da imagem.
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
    params.require(:image).permit(:task_value)
  end

  # Valida se o tipo do arquivo é uma imagem suportada
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

  # Serializa a imagem para JSON
  def image_json(image)
    {
      id: image.id,
      original_filename: image.original_filename,
      storage_path: image.storage_path,
      status: image.status,
      task_value: image.task_value&.to_f,
      uploader: {
        id: image.uploader.id,
        name: image.uploader.name,
        email: image.uploader.email
      },
      reserver: image.reserver ? {
        id: image.reserver.id,
        name: image.reserver.name,
        email: image.reserver.email
      } : nil,
      reserved_at: image.reserved_at,
      created_at: image.created_at,
      updated_at: image.updated_at
    }
  end
end
