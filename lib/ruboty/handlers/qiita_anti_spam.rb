require "active_support/core_ext/hash/keys"
require "akismet"
require "google/api_client/client_secrets"
require "google/apis/bigquery_v2"
require "googleauth"
require "qiita"
require "ruboty"
require "stringio"

module Ruboty
  module Handlers
    class QiitaAntiSpam < Base
      AKISMET_SITE_ROOT_URL = "http://qiita.com"

      # Note that USER_ID_REGEXP also matches a UUID string.
      # When you want to distingish a string, test it with UUID_REGEXP first.
      USER_ID_REGEXP = %r<\w[\w\-]+\w(?:@github)?>
      UUID_REGEXP = %r<[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}>
      ITEM_SPECIFIER_REGEXP = %r<#{UUID_REGEXP}|#{USER_ID_REGEXP}>

      env :AKISMET_API_KEY, "Akismet API key"
      env :GOOGLE_APPLICATION_CREDENTIALS_JSON, "Google application credentials as JSON string"
      env :QIITA_ACCESS_TOKEN, "Qiita access token", optional: true

      on(
        /ham (?<item_spec>#{ITEM_SPECIFIER_REGEXP})\z/,
        description: "Submit an item (article or comment), or all items posted by a user, as ham.",
        name: "submit_ham",
      )

      on(
        /spam (?<item_spec>#{ITEM_SPECIFIER_REGEXP})\z/,
        description: "Submit an item (article or comment), or all items posted by a user, as spam.",
        name: "submit_spam",
      )

      def submit_ham(message)
        submit(message, :ham)
      end

      def submit_spam(message)
        submit(message, :spam)
      end

      private

      # @param message [Ruboty::Message]
      # @param item_kind [:ham, :spam]
      def submit(message, item_kind)
        item_spec = message[:item_spec]
        if item_spec =~ UUID_REGEXP
          events = bigquery_client.fetch_check_spam_events(uuid: item_spec)
        elsif
          permanent_user_id = get_permanent_user_id(item_spec)
          if permanent_user_id.nil?
            message.reply("User #{item_spec} not found.")
            return
          end
          events = bigquery_client.fetch_check_spam_events(permanent_user_id: permanent_user_id)
        end

        lines = []
        begin
          akismet_client.open
          events.each do |ev|
            akismet_client.__send__(item_kind, ev.user_ip, ev.user_agent, ev.other_params)
            lines << "Submitted #{ev.target_url} to Akismet as #{item_kind}."
          end
        ensure
          akismet_client.close
        end

        if lines.empty?
          message.reply("No items found.")
        else
          message.reply(lines.join("\n"))
        end
      rescue
        message.reply("Error: #{$!}")
      end

      # @param user_id [String]
      # @return [Integer, nil]
      def get_permanent_user_id(user_id)
        qiita_client.get_user(user_id).body["permanent_id"].to_i || nil rescue nil
      end

      def akismet_client
        @akismet_client ||= Akismet::Client.new(
          ENV["AKISMET_API_KEY"],
          AKISMET_SITE_ROOT_URL,
        )
      end

      def bigquery_client
        @bigquery_client ||= BigqueryClient.new(
          application_credentials_json: ENV["GOOGLE_APPLICATION_CREDENTIALS_JSON"]
        )
      end

      def qiita_client
        @qiita_client ||= Qiita::Client.new(access_token: ENV["QIITA_ACCESS_TOKEN"])
      end

      class BigqueryClient
        APPLICATION_NAME = "ruboty-qiita_anti_spam"
        AUTH_URI = "https://accounts.google.com/o/oauth2/auth"
        SCOPE = Google::Apis::BigqueryV2::AUTH_BIGQUERY
        TOKEN_URI = "https://accounts.google.com/o/oauth2/token"

        def initialize(application_credentials_json: nil)
          @application_credentials_json = application_credentials_json
        end

        # @options opts [Integer] :permanent_user_id
        # @options opts [String] :uuid
        # return [Array<CheckSpamEvent>]
        def fetch_check_spam_events(opts)
          query_request = build_query_request(opts)
          query_response = bigquery_service.query("qiita-com", query_request)
          (query_response.rows || []).map do |row|
            CheckSpamEvent.new(row)
          end
        end

        private

        def bigquery_service
          @bigquery_service ||= begin
            service = Google::Apis::BigqueryV2::BigqueryService.new
            service.client_options.application_name = APPLICATION_NAME
            service.client_options.application_version = Ruboty::QiitaAntiSpam::VERSION
            service.authorization = authorization
            service
          end
        end

        def authorization
          json_key_io = StringIO.new(@application_credentials_json)
          Google::Auth::ServiceAccountCredentials.new(json_key_io: json_key_io, scope: [SCOPE])
        end

        # @options opts [Integer] :permanent_user_id
        # @options opts [String] :uuid
        # return [Google::Apis::BigqueryV2::QueryRequest]
        def build_query_request(opts)
          if (permanent_user_id = opts[:permanent_user_id])
            cond = %Q(user_id = #{permanent_user_id})
          elsif (uuid = opts[:uuid])
            cond = %Q(message3 = "#{uuid}")
          else
            fail ArgumentError
          end
          # Row spec: message1 = context, message2 = akismet_params, message3 = uuid
          query = <<-EOQ
            SELECT message1, message2
            FROM (TABLE_DATE_RANGE(qiita.events_, DATE_ADD(CURRENT_TIMESTAMP(), -7, "DAY"), CURRENT_TIMESTAMP()))
            WHERE name = "check spam" AND (#{cond})
            LIMIT 1000
          EOQ
          Google::Apis::BigqueryV2::QueryRequest.new(query: query)
        end
      end

      class CheckSpamEvent
        attr_reader :target_url
        attr_reader :other_params, :user_agent, :user_ip

        # @param row [Google::Apis::BigqueryV2::TableRow]
        def initialize(row)
          context = JSON.parse(row.f[0].v).deep_symbolize_keys
          @target_url = context[:target_url]
          akismet_params = JSON.parse(row.f[1].v).deep_symbolize_keys
          @other_params = akismet_params[:other_params]
          @user_agent = akismet_params[:user_agent]
          @user_ip = akismet_params[:user_ip]
        end
      end
    end
  end
end
