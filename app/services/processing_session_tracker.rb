class ProcessingSessionTracker
  ACTIVE_STATUSES = %w[queued running].freeze

  class << self
    def start!(flow:, resource:, scope_key:, progress_key:, started_by_user_id:, job_id:, payload: {})
      now = Time.current

      ProcessingSession.transaction do
        active_scope(flow: flow, resource: resource, scope_key: scope_key)
          .update_all(status: ProcessingSession.statuses[:superseded], finished_at: now, updated_at: now)

        ProcessingSession.create!(
          flow: flow,
          status: :queued,
          resource: resource,
          scope_key: normalized_scope_key(scope_key),
          progress_key: progress_key,
          job_id: job_id,
          started_by_user_id: started_by_user_id,
          payload: payload || {},
          started_at: now,
          last_heartbeat_at: now
        )
      end
    end

    def running!(progress_key:, payload: nil)
      touch!(progress_key: progress_key, status: :running, payload: payload)
    end

    def complete!(progress_key:, payload: nil)
      touch!(progress_key: progress_key, status: :completed, payload: payload, finished: true)
    end

    def fail!(progress_key:, payload: nil)
      touch!(progress_key: progress_key, status: :failed, payload: payload, finished: true)
    end

    def touch!(progress_key:, status:, payload: nil, finished: false)
      session = find_by_progress_key(progress_key)
      return nil unless session

      now = Time.current
      next_payload = payload.nil? ? session.payload : payload

      attributes = {
        status: status,
        payload: next_payload,
        last_heartbeat_at: now,
        updated_at: now
      }
      attributes[:finished_at] = now if finished

      session.update!(attributes)
      session
    end

    def find_active(flow:, resource:, scope_key:)
      active_scope(flow: flow, resource: resource, scope_key: scope_key)
        .order(updated_at: :desc)
        .first
    end

    def find_by_progress_key(progress_key)
      ProcessingSession.find_by(progress_key: progress_key.to_s)
    end

    private

    def active_scope(flow:, resource:, scope_key:)
      ProcessingSession.where(
        flow: flow,
        resource: resource,
        scope_key: normalized_scope_key(scope_key),
        status: ProcessingSession.statuses.values_at(*ACTIVE_STATUSES)
      )
    end

    def normalized_scope_key(scope_key)
      text = scope_key.to_s.strip
      text.presence
    end
  end
end
