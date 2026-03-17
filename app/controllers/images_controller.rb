class ImagesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!, only: [:index, :create, :mark_paid, :expire_reservation, :new]
  before_action :authorize_annotator!, only: [:reserve, :submit]
  before_action :authorize_reviewer!, only: [:start_review, :approve, :reject]
  before_action :set_image, only: [:reserve, :submit, :start_review, :approve, :reject, :mark_paid, :expire_reservation]

  # GET /images
  # Lista todas as imagens cadastradas no sistema
  def index
    @images = Image.includes(:uploader, :reserver).order(created_at: :desc)
    
    render json: @images.map { |image| image_json(image) }
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

    # Validar presença do arquivo
    if uploaded_file.blank?
      return render json: { error: 'Nenhum arquivo foi enviado' }, status: :unprocessable_entity
    end

    # Validar tipo do arquivo
    unless valid_image_type?(uploaded_file)
      return render json: { 
        error: 'Formato de arquivo não suportado. Use JPG, JPEG ou PNG' 
      }, status: :unprocessable_entity
    end

    # Validar tamanho do arquivo (máximo 10MB)
    if uploaded_file.size > 10.megabytes
      return render json: { 
        error: 'Arquivo muito grande. Tamanho máximo: 10MB' 
      }, status: :unprocessable_entity
    end

    # Criar registro da imagem
    image = Image.new(
      original_filename: uploaded_file.original_filename,
      storage_path: '', # Será preenchido após salvar o arquivo
      status: :available,
      task_value: task_value,
      uploader: current_user
    )

    begin
      # Salvar o arquivo no sistema de arquivos
      storage_path = save_uploaded_file(uploaded_file)
      image.storage_path = storage_path

      if image.save
        render json: image_json(image), status: :created
      else
        # Se falhar ao salvar no banco, remover arquivo
        File.delete(Rails.root.join(storage_path)) if File.exist?(Rails.root.join(storage_path))
        render json: { errors: image.errors.full_messages }, status: :unprocessable_entity
      end
    rescue StandardError => e
      # Em caso de erro, garantir que o arquivo seja removido
      File.delete(Rails.root.join(storage_path)) if storage_path && File.exist?(Rails.root.join(storage_path))
      render json: { error: "Erro ao fazer upload: #{e.message}" }, status: :internal_server_error
    end
  end

  # POST /images/:id/reserve
  # Annotator reserves an available image
  def reserve
    begin
      @image.reserve!(current_user)
      render json: image_json(@image), status: :ok
    rescue Image::StateMachineError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # POST /images/:id/submit
  # Annotator submits annotation for reserved image
  def submit
    begin
      # Pega os arquivos do params e passa para o model
      @image.submit!(current_user, params[:projeto_tar], params[:dados_csv], params[:config_json])
      render json: image_json(@image), status: :ok
    rescue Image::StateMachineError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # POST /images/:id/start_review
  # Reviewer starts reviewing a submitted annotation
  def start_review
    begin
      @image.start_review!(current_user)
      render json: image_json(@image), status: :ok
    rescue Image::StateMachineError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # POST /images/:id/approve
  # Reviewer approves annotation in review
  def approve
    begin
      @image.approve!(current_user)
      render json: image_json(@image), status: :ok
    rescue Image::StateMachineError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # POST /images/:id/reject
  # Reviewer rejects annotation in review
  def reject
    begin
      @image.reject!(current_user)
      render json: image_json(@image), status: :ok
    rescue Image::StateMachineError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # POST /images/:id/mark_paid
  # Admin marks approved annotation as paid
  def mark_paid
    begin
      @image.mark_as_paid!(current_user)
      render json: image_json(@image), status: :ok
    rescue Image::StateMachineError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # POST /images/:id/expire_reservation
  # Admin manually expires a reservation
  def expire_reservation
    begin
      @image.expire_reservation!
      render json: image_json(@image), status: :ok
    rescue Image::StateMachineError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def set_image
    @image = Image.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Image not found' }, status: :not_found
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
