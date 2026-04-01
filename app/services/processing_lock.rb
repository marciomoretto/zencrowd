class ProcessingLock
  LUA_RELEASE = <<~LUA
    if redis.call('get', KEYS[1]) == ARGV[1] then
      return redis.call('del', KEYS[1])
    end
    return 0
  LUA

  class << self
    def with_lock(key, ttl_seconds: 900)
      token = SecureRandom.hex(16)
      locked = acquire(key: key, token: token, ttl_seconds: ttl_seconds)
      return false unless locked

      yield
      true
    ensure
      release(key: key, token: token) if locked
    end

    private

    def acquire(key:, token:, ttl_seconds:)
      redis.set(key, token, nx: true, ex: ttl_seconds)
    rescue StandardError => e
      Rails.logger.error("Falha ao adquirir lock #{key}: #{e.class} - #{e.message}")
      false
    end

    def release(key:, token:)
      redis.eval(LUA_RELEASE, keys: [key], argv: [token])
    rescue StandardError => e
      Rails.logger.warn("Falha ao liberar lock #{key}: #{e.class} - #{e.message}")
      nil
    end

    def redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    end
  end
end
