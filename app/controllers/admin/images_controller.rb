class Admin::ImagesController < ApplicationController
  before_action :require_admin!

  def index
    @tiles = Tile.order(id: :desc)
  end

  def new
    # Apenas renderiza o formulário
  end

  def create
    if params[:images].blank?
      flash[:alert] = 'Selecione pelo menos um tile.'
      return redirect_to new_admin_tile_path
    end

    uploaded_files = params[:images]
    saved = 0
    counted_count = 0
    message_counts = Hash.new(0)
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

      tile = Tile.new(
        original_filename: file.original_filename,
        storage_path: "storage/uploads/images/#{filename}",
        status: :available,
        uploader: current_user
      )
      if tile.save
        saved += 1

        count_result = TileHeadCounter.call(tile: tile, expose_error: true)
        if count_result[:status] == :ok
          counted_count += 1
        elsif count_result[:message].present?
          message_counts[count_result[:message]] += 1
        end
      else
        errors << "Erro ao salvar #{file.original_filename}: #{tile.errors.full_messages.join(', ')}"
        File.delete(storage_path) if File.exist?(storage_path)
      end
    end

    summary_message = nil
    if saved.positive?
      missing_count = [saved - counted_count, 0].max
      summary_message = "Contagem de cabeças em #{counted_count} de #{saved} tile(s)."
      summary_message += " #{missing_count} tile(s) sem contagem." if missing_count.positive?

      principal_reason = message_counts.max_by { |_, count| count }&.first
      summary_message += " Motivo principal: #{principal_reason}." if principal_reason.present?
    end

    if errors.empty?
      flash[:notice] = ["#{saved} tile(s) enviado(s) com sucesso.", summary_message].compact.join(' ')
      redirect_to admin_tiles_path
    else
      flash[:alert] = [errors.join(' '), summary_message].compact.join(' ')
      redirect_to new_admin_tile_path
    end
  end

  private

  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: 'Acesso restrito ao administrador.'
    end
  end
end
