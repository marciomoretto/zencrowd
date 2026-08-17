class MosaicStorage
  class << self
    def root
      Rails.root.join('storage', 'mosaics')
    end

    def event_dir(evento_id:, pasta_nome:)
      root.join("evento_#{evento_id}", safe_fragment(pasta_nome))
    end

    def ensure_event_dir(evento_id:, pasta_nome:)
      dir = event_dir(evento_id: evento_id, pasta_nome: pasta_nome)
      FileUtils.mkdir_p(dir)
      dir
    end

    def absolute_path_from_url(url)
      value = url.to_s.strip
      return nil unless value.start_with?('/mosaics/')

      absolute_path(value.delete_prefix('/mosaics/'))
    end

    def absolute_path(relative_path)
      value = relative_path.to_s
      return nil if value.blank? || value.include?("\0")

      cleaned = Pathname.new(value).cleanpath.to_s
      return nil if cleaned == '.' || cleaned.start_with?('..')

      root_path = root.expand_path
      absolute = root_path.join(cleaned).expand_path
      return nil unless absolute.to_s.start_with?("#{root_path}/")

      absolute
    end

    def url_for_absolute_path(path)
      absolute = Pathname.new(path.to_s).expand_path.to_s
      root_path = root.expand_path.to_s
      return nil unless absolute.start_with?("#{root_path}/")

      relative = absolute.delete_prefix("#{root_path}/")
      "/mosaics/#{relative}"
    end

    private

    def safe_fragment(value)
      text = value.to_s.strip
      text = 'sem_pasta' if text.empty?
      text.gsub(/[^a-zA-Z0-9._-]/, '_')
    end
  end
end