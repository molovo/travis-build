require 'json'
require 'rack/ssl'
require 'sinatra/base'
require 'metriks'

require 'travis/build'
require 'travis/api/build/sentry'
require 'travis/api/build/metriks'
require 'logger'

module Travis
  module Api
    module Build
      class App < Sinatra::Base
        enable :static
        set :root, File.expand_path('../../../../../', __FILE__)
        set :start, Time.now.utc

        configure(:production, :staging) do
          use Rack::SSL
        end

        configure do
          use Sentry unless Travis::Build.config.sentry_dsn.to_s.empty?
          use Metriks unless Travis::Build.config.librato.email.to_s.empty? ||
                             Travis::Build.config.librato.token.to_s.empty? ||
                             Travis::Build.config.librato.source.to_s.empty?

          use Rack::Deflater

          enable :logging
        end

        helpers do
          def auth_disabled?
            Travis::Build.config.auth_disabled? ||
            api_tokens.empty? && (
              settings.development? || settings.test?
            )
          end

          def api_tokens
            @api_tokens ||=
              Travis::Build.config.api_token.to_s.split(',').map(&:strip)
          end
        end

        before '/script' do
          return if auth_disabled?

          unless env.key?('HTTP_AUTHORIZATION')
            halt 401, 'missing Authorization header'
          end

          type, token = env['HTTP_AUTHORIZATION'].to_s.split(' ', 2)

          api_tokens.each do |valid_token|
            return if Rack::Utils.secure_compare(type, 'token') &&
                      Rack::Utils.secure_compare(token, valid_token)
          end

          halt 403, 'access denied'
        end

        error JSON::ParserError do
          status 400
          env['sinatra.error'].message
        end

        error do
          status 500
          env['sinatra.error'].message
        end

        post '/script' do
          env['rack.logger'] = ::Logger.new(STDERR)
          logger.level = ::Logger.const_get(Travis::Build.config.log_level)

          request_json = request.body.read
          payload = JSON.parse(request_json)
          logger.debug "request_json=#{request_json}"

          unless Travis::Build.config.sentry_dsn.empty?
            Raven.extra_context(
              repository: payload.fetch('repository', {}).fetch('slug', '???'),
              job: payload.fetch('job', {}).fetch('id', '???'),
            )
          end

          compiled = Travis::Build.script(payload).compile
          logger.debug "compiled_script=#{compiled}"

          content_type 'application/x-sh'
          status 200
          compiled
        end

        get('/') { uptime }
        get('/uptime') { uptime }
        get('/boom') { raise StandardError, ':bomb:' }

        private

        def uptime
          headers(
            'Travis-Build-Uptime' => "#{Time.now.utc - settings.start}s",
            'Travis-Build-Version' => Travis::Build.version
          )
          status 204
        end
      end
    end
  end
end
