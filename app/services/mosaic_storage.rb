class MosaicStorage
  class << self
    def root
      roots.first
    end

    def roots
      [
        Rails.root.join('storage', 'mosaics'),
        Rails.root.join('public', 'mosaics')
      ].uniq
    end

    def event_dir(evento_id:, pasta_nome:)
      dirs = event_dirs(evento_id: evento_id, pasta_nome: pasta_nome)
      dirs.find { |dir| Dir.exist?(dir) } || dirs.first
    end

    def event_dirs(evento_id:, pasta_nome:)
      roots.map { |base| base.join("evento_#{evento_id}", safe_fragment(pasta_nome)) }
    end

    def ensure_event_dir(evento_id:, pasta_nome:)
      ensure_event_dirs(evento_id: evento_id, pasta_nome: pasta_nome).first || event_dir(evento_id: evento_id, pasta_nome: pasta_nome)
    end

    def ensure_event_dirs(evento_id:, pasta_nome:)
      event_dirs(evento_id: evento_id, pasta_nome: pasta_nome).filter_map do |dir|
        begin
          FileUtils.mkdir_p(dir)
          dir
        rescue StandardError
          nil
        end
      end
    end

    def absolute_path_from_url(url, prefer_existing: false)
      value = url.to_s.strip
      return nil unless value.start_with?('/mosaics/')

      absolute_path(value.delete_prefix('/mosaics/'), prefer_existing: prefer_existing)
    end

    def absolute_path(relative_path, prefer_existing: false)
      value = relative_path.to_s
      return nil if value.blank? || value.include?("\0")

      cleaned = Pathname.new(value).cleanpath.to_s
      return nil if cleaned == '.' || cleaned.start_with?('..')

      candidates = roots.filter_map do |base|
        root_path = base.expand_path
        absolute = root_path.join(cleaned).expand_path
        next unless absolute.to_s.start_with?("#{root_path}/")

        absolute
      end

      return nil if candidates.empty?

      if prefer_existing
        candidates.find { |candidate| File.exist?(candidate) }
      else
        candidates.first
      end
    end

    def absolute_existing_path(relative_path)
      absolute_path(relative_path, prefer_existing: true)
    end

    def sync_to_other_roots(path)
      absolute = Pathname.new(path.to_s).expand_path
      relative = relative_path_for_absolute(absolute)
      return nil if relative.blank?

      source = absolute.to_s
      roots.each do |base|
        target = base.expand_path.join(relative)
        next if target.to_s == source

        begin
          FileUtils.mkdir_p(target.dirname)
          FileUtils.cp(source, target.to_s)
        rescue StandardError
          nil
        end
      end

      true
    rescue StandardError
      nil
    end

    def relative_path_for_absolute(path)
      absolute = Pathname.new(path.to_s).expand_path.to_s

      roots.each do |base|
        base_path = base.expand_path.to_s
        next unless absolute.start_with?("#{base_path}/")

        return absolute.delete_prefix("#{base_path}/")
      end

      nil
    end

    def url_for_absolute_path(path)
      relative = relative_path_for_absolute(path)
      return nil if relative.blank?

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