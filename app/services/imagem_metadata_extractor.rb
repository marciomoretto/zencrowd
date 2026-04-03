require 'exifr/jpeg'
require 'rexml/document'
require 'time'

class ImagemMetadataExtractor
  class << self
    def extract(uploaded_file)
      with_local_path(uploaded_file) do |path|
        return empty_payload unless path && File.file?(path)

        exif_data = extract_exif(path)
        xmp_data = deep_serialize(extract_xmp(path))

        {
          exif: exif_data,
          xmp: xmp_data,
          normalized: normalized_attributes(exif_data, xmp_data)
        }
      end
    rescue StandardError => e
      Rails.logger.warn("ImagemMetadataExtractor falhou: #{e.class} - #{e.message}")
      empty_payload
    end

    private

    def empty_payload
      {
        exif: {},
        xmp: {},
        normalized: {
          data_hora: Time.current.change(sec: 0),
          gps_location: '0.000000,0.000000',
          cidade: 'Nao informada',
          local: 'Nao informado'
        }
      }
    end

    def resolve_file_path(uploaded_file)
      return uploaded_file.path if uploaded_file.respond_to?(:path)
      return uploaded_file.tempfile.path if uploaded_file.respond_to?(:tempfile) && uploaded_file.tempfile

      nil
    end

    def with_local_path(uploaded_file)
      path = resolve_file_path(uploaded_file)
      return yield(path) if path.present?

      blob = resolve_blob(uploaded_file)
      unless blob
        Rails.logger.info('ImagemMetadataExtractor: arquivo sem path local e sem blob associado; retornando payload vazio')
        return yield(nil)
      end

      blob.open do |tempfile|
        yield(tempfile.path)
      end
    end

    def resolve_blob(uploaded_file)
      return uploaded_file.blob if uploaded_file.respond_to?(:blob)

      if uploaded_file.respond_to?(:attachment) && uploaded_file.attachment.respond_to?(:blob)
        return uploaded_file.attachment.blob
      end

      nil
    end

    def extract_exif(path)
      image = EXIFR::JPEG.new(path)
      return {} unless image.exif?

      exif_hash = {}

      add_exif_field(exif_hash, 'date_time_original', image, :date_time_original)
      add_exif_field(exif_hash, 'date_time', image, :date_time)
      add_exif_field(exif_hash, 'date_time_digitized', image, :date_time_digitized)
      add_exif_field(exif_hash, 'make', image, :make)
      add_exif_field(exif_hash, 'model', image, :model)
      add_exif_field(exif_hash, 'software', image, :software)
      add_exif_field(exif_hash, 'orientation', image, :orientation)
      add_exif_field(exif_hash, 'width', image, :width)
      add_exif_field(exif_hash, 'height', image, :height)

      if image.respond_to?(:gps_latitude) && !blank_value?(image.gps_latitude)
        exif_hash['gps_latitude_raw'] = deep_serialize(image.gps_latitude)
      end

      if image.respond_to?(:gps_longitude) && !blank_value?(image.gps_longitude)
        exif_hash['gps_longitude_raw'] = deep_serialize(image.gps_longitude)
      end

      latitude = read_coordinate(image, :latitude)
      longitude = read_coordinate(image, :longitude)

      if latitude.nil? && image.respond_to?(:gps_latitude) && image.respond_to?(:gps_latitude_ref)
        latitude = dms_to_decimal(image.gps_latitude, image.gps_latitude_ref)
      end

      if longitude.nil? && image.respond_to?(:gps_longitude) && image.respond_to?(:gps_longitude_ref)
        longitude = dms_to_decimal(image.gps_longitude, image.gps_longitude_ref)
      end

      exif_hash['gps_latitude'] = latitude unless latitude.nil?
      exif_hash['gps_longitude'] = longitude unless longitude.nil?

      exif_hash
    rescue StandardError => e
      Rails.logger.warn("ImagemMetadataExtractor extract_exif falhou: #{e.class} - #{e.message}")
      {}
    end

    def add_exif_field(target, key, image, method_name)
      return unless image.respond_to?(method_name)

      value = image.public_send(method_name)
      return if blank_value?(value)

      target[key] = deep_serialize(value)
    rescue StandardError
      nil
    end

    def dms_to_decimal(value, ref = nil)
      return nil if blank_value?(value)

      parts = Array(value).map { |v| v.is_a?(Rational) ? v.to_f : v.to_f }
      return nil if parts.empty?

      degrees = parts[0] || 0.0
      minutes = parts[1] || 0.0
      seconds = parts[2] || 0.0

      decimal = degrees + (minutes / 60.0) + (seconds / 3600.0)
      decimal *= -1 if %w[S W].include?(ref.to_s.upcase)
      decimal
    rescue StandardError
      nil
    end

    def read_coordinate(image, axis)
      value = extract_from_container(image, axis)
      value ||= extract_from_container(image.respond_to?(:gps) ? image.gps : nil, axis)

      return nil if value.nil?

      Float(value)
    rescue StandardError
      nil
    end

    def extract_from_container(container, key)
      return nil if container.nil?

      if container.respond_to?(key)
        return container.public_send(key)
      end

      return nil unless container.is_a?(Hash)

      candidates = [
        key,
        key.to_s,
        key.to_s.upcase,
        "gps_#{key}",
        "GPS#{key.to_s.capitalize}"
      ]

      candidates.each do |candidate|
        return container[candidate] if container.key?(candidate)
      end

      nil
    end

    def extract_xmp(path)
      binary = File.binread(path)
      packets = binary.scan(/<x:xmpmeta[\s\S]*?<\/x:xmpmeta>/i)

      if packets.empty?
        rdf_nodes = binary.scan(/<rdf:RDF[\s\S]*?<\/rdf:RDF>/i)
        packets = rdf_nodes.map { |node| "<x:xmpmeta>#{node}</x:xmpmeta>" }
      end

      return {} if packets.empty?

      parsed_packets = packets.map.with_index(1) do |packet, index|
        ["packet_#{index}", parse_xmp_packet(packet)]
      end.to_h

      return parsed_packets['packet_1'] if parsed_packets.size == 1

      parsed_packets
    rescue StandardError
      {}
    end

    def parse_xmp_packet(packet)
      xml = packet.dup.force_encoding('UTF-8')
      xml = xml.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      document = REXML::Document.new(xml)
      root = document.root
      return {} unless root

      element_to_hash(root)
    rescue StandardError
      {}
    end

    def element_to_hash(element)
      result = {}

      element.attributes.each_attribute do |attribute|
        key = "@#{qualified_name(attribute.prefix, attribute.name)}"
        result[key] = attribute.value
      end

      text_value = element.texts.map(&:value).join(' ').strip
      result['_text'] = text_value unless text_value.empty?

      grouped_children = element.elements.to_a.group_by { |child| qualified_name(child.prefix, child.name) }

      grouped_children.each do |child_name, children|
        values = children.map { |child| element_to_hash(child) }
        result[child_name] = values.size == 1 ? values.first : values
      end

      result
    end

    def qualified_name(prefix, name)
      prefix && !prefix.empty? ? "#{prefix}:#{name}" : name
    end

    def deep_serialize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, inner_value), result|
          result[sanitize_string(key.to_s)] = deep_serialize(inner_value)
        end
      when Array
        value.map { |item| deep_serialize(item) }
      when Time, DateTime
        value.iso8601
      when Date
        value.to_s
      when Rational
        value.to_f
      when String
        sanitize_string(value)
      when Numeric, TrueClass, FalseClass, NilClass
        value
      else
        sanitize_string(value.to_s)
      end
    end

    def sanitize_string(value)
      text = value.to_s
      normalized = text.encode('UTF-8', text.encoding, invalid: :replace, undef: :replace, replace: '')
      normalized.delete("\u0000")
    rescue StandardError
      text.to_s.force_encoding('UTF-8').scrub('').delete("\u0000")
    end

    def normalized_attributes(exif_data, xmp_data)
      flattened = flatten_metadata({ 'exif' => exif_data, 'xmp' => xmp_data })

      date_raw = find_first_value(flattened, %w[datetimeoriginal datetime digitized createdate datecreated metadatadate])
      latitude = find_first_numeric(flattened, %w[gpslatitude latitude])
      longitude = find_first_numeric(flattened, %w[gpslongitude longitude])

      if latitude.nil? || longitude.nil?
        pair = find_coordinate_pair(flattened)
        latitude ||= pair&.first
        longitude ||= pair&.last
      end

      city = find_first_string(flattened, %w[photoshopcity city locality])
      place = find_first_string(flattened, %w[sublocation location locationname place])

      geocoded = reverse_geocode(latitude, longitude)
      city = geocoded[:city] || city
      place = geocoded[:local] || place

      {
        data_hora: parse_datetime(date_raw) || Time.current.change(sec: 0),
        gps_location: latitude && longitude ? format('%.6f,%.6f', latitude, longitude) : '0.000000,0.000000',
        cidade: city || 'Nao informada',
        local: place || 'Nao informado'
      }
    end

    def reverse_geocode(latitude, longitude)
      return {} unless valid_coordinates_for_geocoder?(latitude, longitude)

      result = Geocoder.search([latitude, longitude]).first
      return {} unless result

      address = extract_address_hash(result)

      city = first_present_value(
        safe_result_value(result, :city),
        address['city'],
        address['town'],
        address['village'],
        address['municipality'],
        address['county']
      )

      road = first_present_value(address['road'], address['pedestrian'])
      neighborhood = first_present_value(address['neighbourhood'], address['suburb'], address['hamlet'])

      local = first_present_value(road, neighborhood, safe_result_value(result, :address))
      local = strip_trailing_house_number(local)

      {
        city: sanitize_string(city.to_s).presence,
        local: sanitize_string(local.to_s).presence
      }
    rescue StandardError => e
      Rails.logger.warn("Geocoder reverse falhou: #{e.class} - #{e.message}")
      {}
    end

    def valid_coordinates_for_geocoder?(latitude, longitude)
      return false if latitude.nil? || longitude.nil?
      return false unless latitude.between?(-90.0, 90.0)
      return false unless longitude.between?(-180.0, 180.0)
      return false if latitude.zero? && longitude.zero?

      true
    end

    def extract_address_hash(result)
      data = result.respond_to?(:data) ? result.data : {}
      return {} unless data.is_a?(Hash)

      raw_address = data['address'] || data[:address] || {}
      return {} unless raw_address.is_a?(Hash)

      raw_address.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end

    def safe_result_value(result, method_name)
      return nil unless result.respond_to?(method_name)

      result.public_send(method_name)
    rescue StandardError
      nil
    end

    def first_present_value(*values)
      values.flatten.find { |value| value.present? }
    end

    def strip_trailing_house_number(value)
      return nil if blank_value?(value)

      normalized = value.to_s.strip
      without_number = normalized.gsub(/[\s,]+\d+[[:alnum:]\/-]*\z/, '').strip
      without_number.presence || normalized
    end

    def flatten_metadata(value, prefix = nil, result = {})
      case value
      when Hash
        value.each do |key, inner_value|
          new_prefix = prefix ? "#{prefix}.#{key}" : key.to_s
          flatten_metadata(inner_value, new_prefix, result)
        end
      when Array
        value.each_with_index do |inner_value, index|
          new_prefix = "#{prefix}[#{index}]"
          flatten_metadata(inner_value, new_prefix, result)
        end
      else
        result[prefix] = value unless prefix.nil?
      end

      result
    end

    def find_first_value(flattened, key_fragments)
      normalized_fragments = key_fragments.map { |fragment| normalize_key(fragment) }

      normalized_fragments.each do |fragment|
        flattened.each do |key, value|
          next if blank_value?(value)

          normalized_key = normalize_key(key)
          return value if normalized_key.include?(fragment)
        end
      end

      nil
    end

    def find_first_numeric(flattened, key_fragments)
      normalized_fragments = key_fragments.map { |fragment| normalize_key(fragment) }

      normalized_fragments.each do |fragment|
        flattened.each do |key, value|
          next if blank_value?(value)

          normalized_key = normalize_key(key)
          next unless normalized_key.include?(fragment)

          begin
            return Float(value)
          rescue StandardError
            next
          end
        end
      end

      nil
    end

    def find_coordinate_pair(flattened)
      raw = find_first_value(flattened, %w[gpscoordinates gpsposition coordinates])
      return nil if raw.nil?

      matches = raw.to_s.scan(/-?\d+(?:\.\d+)?/)
      return nil if matches.size < 2

      [Float(matches[0]), Float(matches[1])]
    rescue StandardError
      nil
    end

    def find_first_string(flattened, key_fragments)
      value = find_first_value(flattened, key_fragments)
      return nil if blank_value?(value)

      value.to_s.strip
    end

    def parse_datetime(value)
      return value if value.is_a?(Time)
      return nil if blank_value?(value)

      if value.is_a?(String)
        normalized = value.to_s.strip
        normalized = normalized.sub(/\A(\d{4}):(\d{2}):(\d{2})/, '\\1-\\2-\\3')

        return Time.zone.parse(normalized) if Time.zone

        return Time.parse(normalized)
      end

      return value.to_time if value.respond_to?(:to_time)

      normalized = value.to_s.strip
      normalized = normalized.sub(/\A(\d{4}):(\d{2}):(\d{2})/, '\\1-\\2-\\3')

      Time.zone ? Time.zone.parse(normalized) : Time.parse(normalized)
    rescue StandardError
      nil
    end

    def normalize_key(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, '')
    end

    def blank_value?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || value.to_s.strip.empty?
    end
  end
end
