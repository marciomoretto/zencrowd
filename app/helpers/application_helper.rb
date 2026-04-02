module ApplicationHelper
	def render_markdown(content)
		text = content.to_s
		return ''.html_safe if text.strip.empty?
		return simple_format(h(text)) unless markdown_available?

		rendered = markdown_engine.render(text)
		sanitize(
			rendered,
			tags: %w[p br blockquote pre code span h1 h2 h3 h4 h5 h6 ul ol li em strong a table thead tbody tr th td hr],
			attributes: %w[href title class rel target]
		)
	rescue StandardError
		simple_format(h(text))
	end

	def markdown_highlight_css
		return '' unless markdown_available?

		::Rouge::Themes::GitHub.render(scope: '.markdown-body .highlight').html_safe
	end

	def markdown_engine
		@markdown_engine ||= ::Redcarpet::Markdown.new(
			markdown_renderer_class.new(
				filter_html: true,
				hard_wrap: true,
				link_attributes: {
					rel: 'nofollow noopener noreferrer',
					target: '_blank'
				}
			),
			autolink: true,
			fenced_code_blocks: true,
			tables: true,
			strikethrough: true,
			no_intra_emphasis: true,
			lax_spacing: true
		)
	end

	def markdown_renderer_class
		@markdown_renderer_class ||= Class.new(::Redcarpet::Render::HTML) do
			include ::Rouge::Plugins::Redcarpet
		end
	end

	def markdown_available?
		defined?(::Redcarpet::Markdown) && defined?(::Rouge::Themes::GitHub)
	end

	def human_tile_status(status)
		status_key = status.to_s
		fallback_labels = {
			'available' => 'Disponível',
			'legacy' => 'Legado',
			'abandoned' => 'Abandonada',
			'reserved' => 'Reservada',
			'submitted' => 'Submetida',
			'in_review' => 'Em revisão',
			'approved' => 'Aprovada',
			'payment_requested' => 'Pagamento solicitado',
			'rejected' => 'Rejeitada',
			'paid' => 'Paga'
		}

		I18n.t("activerecord.attributes.image.statuses.#{status_key}", default: fallback_labels[status_key] || status_key.humanize)
	end

	def human_image_status(status)
		human_tile_status(status)
	end

	def tile_status_button_class(status)
		case status.to_s
		when 'available'
			'btn btn-sm btn-outline-success disabled'
		when 'legacy'
			'btn btn-sm btn-outline-secondary disabled'
		when 'abandoned'
			'btn btn-sm btn-outline-warning disabled'
		when 'reserved'
			'btn btn-sm btn-outline-primary disabled'
		when 'submitted'
			'btn btn-sm btn-info disabled text-dark'
		when 'in_review'
			'btn btn-sm btn-outline-primary disabled'
		when 'approved'
			'btn btn-sm btn-outline-success disabled'
		when 'payment_requested'
			'btn btn-sm btn-outline-warning disabled'
		when 'rejected'
			'btn btn-sm btn-outline-danger disabled'
		when 'paid'
			'btn btn-sm btn-success disabled'
		else
			'btn btn-sm btn-secondary disabled'
		end
	end

	def human_review_status(status)
		status_key = status.to_s
		fallback_labels = {
			'approved' => 'Aprovada',
			'rejected' => 'Rejeitada'
		}

		I18n.t("activerecord.attributes.review.statuses.#{status_key}", default: fallback_labels[status_key] || status_key.humanize)
	end

	def evento_categoria_button_class(categoria)
		case categoria.to_s
		when 'direita'
			'btn-primary evento-categoria-direita'
		when 'esquerda'
			'btn-danger'
		when 'outro'
			'btn-secondary'
		else
			'btn-outline-secondary'
		end
	end

	def evento_nome_formatado(evento)
		nome = evento&.nome.to_s
		cidade = evento&.cidade.presence || 'Sem cidade'
		data = evento&.data&.strftime('%d/%m/%y') || '--/--/--'

		"#{nome} - #{cidade} #{data}"
	end

	def imagem_data_hora_origem(imagem)
		flattened = flatten_metadata_for_datetime(
			'exif' => imagem.exif_metadata || {},
			'xmp' => imagem.xmp_metadata || {}
		)

		raw = find_first_metadata_datetime_value(
			flattened,
			%w[datetimeoriginal datetime digitized createdate datecreated metadatadate]
		)

		parse_metadata_datetime_for_display(raw)
	end

	def flatten_metadata_for_datetime(value, prefix = nil, result = {})
		case value
		when Hash
			value.each do |key, inner_value|
				new_prefix = prefix ? "#{prefix}.#{key}" : key.to_s
				flatten_metadata_for_datetime(inner_value, new_prefix, result)
			end
		when Array
			value.each_with_index do |inner_value, index|
				new_prefix = "#{prefix}[#{index}]"
				flatten_metadata_for_datetime(inner_value, new_prefix, result)
			end
		else
			result[prefix] = value unless prefix.nil?
		end

		result
	end

	def find_first_metadata_datetime_value(flattened, key_fragments)
		normalized_fragments = key_fragments.map { |fragment| normalize_metadata_key_for_datetime(fragment) }

		normalized_fragments.each do |fragment|
			flattened.each do |key, value|
				next if blank_metadata_value?(value)

				normalized_key = normalize_metadata_key_for_datetime(key)
				return value if normalized_key.include?(fragment)
			end
		end

		nil
	end

	def parse_metadata_datetime_for_display(value)
		return value if value.is_a?(Time)
		return nil if blank_metadata_value?(value)

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

	def normalize_metadata_key_for_datetime(value)
		value.to_s.downcase.gsub(/[^a-z0-9]/, '')
	end

	def blank_metadata_value?(value)
		value.nil? || (value.respond_to?(:empty?) && value.empty?) || value.to_s.strip.empty?
	end

	def middle_truncate(text, max_length: 36, omission: '...')
		value = text.to_s
		return value if value.length <= max_length

		usable = max_length - omission.length
		return value.first(max_length) if usable <= 1

		left = (usable / 2.0).ceil
		right = usable - left

		"#{value.first(left)}#{omission}#{value.last(right)}"
	end

	def user_role_label(role)
		labels = {
			'admin' => 'Administrador',
			'finance' => 'Financeiro',
			'uploader' => 'Uploader',
			'annotator' => 'Anotador',
			'reviewer' => 'Revisor'
		}

		labels.fetch(role.to_s, role.to_s.humanize)
	end

	# Retorna os links de navegação por papel do usuário autenticado.
	def navigation_links_for(user)
		return [] unless user

		case
		when user.admin?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: uploader_eventos_path, icon: 'bi-calendar-event', label: 'Eventos' },
				{ path: imagens_path, icon: 'bi-image', label: 'Imagens' },
				{ path: tiles_path, icon: 'bi-grid-3x3-gap', label: 'Tiles' },
				{ path: reviewer_reviews_path, icon: 'bi-check-circle', label: 'Tarefas em Revisão' },
				{ path: datasets_path, icon: 'bi-database', label: 'Datasets' },
				{ path: admin_payments_path, icon: 'bi-cash-coin', label: 'Pagamentos' },
				{ path: admin_users_path, icon: 'bi-people', label: 'Usuários' },
				{ path: uploader_drone_settings_path, icon: 'bi-airplane', label: 'Drones' },
				{ path: admin_settings_path, icon: 'bi-sliders', label: 'Configurações' },
			]
		when user.uploader?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: uploader_eventos_path, icon: 'bi-calendar-event', label: 'Eventos' },
				{ path: uploader_drone_settings_path, icon: 'bi-airplane', label: 'Drones' }
			]
		when user.annotator?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: available_tiles_path, icon: 'bi-grid-3x3-gap', label: 'Tarefas Disponíveis' },
				{ path: my_task_path, icon: 'bi-pencil-square', label: 'Tarefa Atual' },
				{ path: completed_tasks_path, icon: 'bi-check2-square', label: 'Minhas Tarefas' }
			]
		when user.reviewer?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: reviewer_reviews_path, icon: 'bi-check-circle', label: 'Tarefas em Revisão' }
			]
		when user.finance?
			[
				{ path: dashboard_path, icon: 'bi-speedometer2', label: 'Dashboard' },
				{ path: admin_payments_path, icon: 'bi-cash-coin', label: 'Pagamentos' }
			]
		else
			[]
		end
	end
end
