class Admin::ImagesController < ApplicationController
  before_action :require_admin!

  def index
    @images = Image.order(id: :desc)
  end

  def new
    # Apenas renderiza o formulário
  end

  def create
    if params[:images].blank? || params[:task_value].blank?
      flash[:alert] = 'Selecione pelo menos uma imagem e defina o valor da tarefa.'
      return redirect_to new_admin_image_path
    end

    uploaded_files = params[:images]
    task_value = params[:task_value]
    saved = 0
    errors = []

    uploaded_files.each do |file|
      unless file.content_type.in?(['image/jpeg', 'image/jpg', 'image/png'])
        errors << "Arquivo #{file.original_filename} possui formato inválido."
        next
      end

      # Salvar arquivo no storage/uploads/images
      upload_dir = Rails.root.join('storage', 'uploads', 'images')
      FileUtils.mkdir_p(upload_dir) unless Dir.exist?(upload_dir)
      timestamp = Time.current.strftime('%Y%m%d%H%M%S')
      random_token = SecureRandom.hex(8)
      extension = File.extname(file.original_filename)
      filename = "#{timestamp}_#{random_token}#{extension}"
      storage_path = upload_dir.join(filename)

      File.open(storage_path, 'wb') { |f| f.write(file.read) }

      image = Image.new(
        original_filename: file.original_filename,
        storage_path: "storage/uploads/images/#{filename}",
        status: :available,
        task_value: task_value,
        uploader: current_user
      )
      if image.save
        saved += 1
      else
        errors << "Erro ao salvar #{file.original_filename}: #{image.errors.full_messages.join(', ')}"
        File.delete(storage_path) if File.exist?(storage_path)
      end
    end

    if errors.empty?
      flash[:notice] = "#{saved} imagem(ns) enviada(s) com sucesso."
      redirect_to admin_images_path
    else
      flash[:alert] = errors.join(' ')
      redirect_to new_admin_image_path
    end
  end

  private

  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: 'Acesso restrito ao administrador.'
    end
  end
end
