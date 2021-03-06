module Cronofy
  # Public: Primary class for interacting with the Cronofy API.
  class Client
    # Public: The scope to request if none is explicitly specified by the
    # caller.
    DEFAULT_OAUTH_SCOPE = %w{
      read_account
      read_events
      create_event
      delete_event
    }.freeze

    # Public: Initialize a new Cronofy::Client.
    #
    # options - A Hash of options used to initialize the client (default: {}):
    #           :access_token  - An existing access token String for the user's
    #                            account (optional).
    #           :client_id     - The client ID String of your Cronofy OAuth
    #                            application (default:
    #                            ENV["CRONOFY_CLIENT_ID"]).
    #           :client_secret - The client secret String of your Cronofy OAuth
    #                            application (default:
    #                            ENV["CRONOFY_CLIENT_SECRET"]).
    #           :refresh_token - An existing refresh token String for the user's
    #                            account (optional).
    def initialize(options = {})
      access_token  = options[:access_token]
      client_id     = options.fetch(:client_id, ENV["CRONOFY_CLIENT_ID"])
      client_secret = options.fetch(:client_secret, ENV["CRONOFY_CLIENT_SECRET"])
      refresh_token = options[:refresh_token]

      @auth = Auth.new(client_id, client_secret, access_token, refresh_token)
    end

    # Public: Lists all the calendars for the account.
    #
    # See http://www.cronofy.com/developers/api#calendars for reference.
    #
    # Returns an Array of Calendars
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def list_calendars
      response = get("/v1/calendars")
      parse_collection(Calendar, "calendars", response)
    end

    # Public: Creates or updates an event for the event_id in the calendar
    # relating to the given calendar_id.
    #
    # calendar_id - The String Cronofy ID for the calendar to upsert the event
    #               to.
    # event       - A Hash describing the event with symbolized keys:
    #               :event_id    - A String uniquely identifying the event for
    #                              your application (note: this is NOT an ID
    #                              generated by Cronofy).
    #               :summary     - A String to use as the summary, sometimes
    #                              referred to as the name or title, of the
    #                              event.
    #               :description - A String to use as the description, sometimes
    #                              referred to as the notes or body, of the
    #                              event.
    #               :start       - The Time the event starts.
    #               :end         - The Time the event ends.
    #               :location    - A Hash describing the location of the event
    #                              with symbolized keys (optional):
    #                              :description - A String describing the
    #                                             location.
    #
    # Examples
    #
    #   client.upsert_event(
    #     "cal_n23kjnwrw2_jsdfjksn234",
    #     event_id: "qTtZdczOccgaPncGJaCiLg",
    #     summary: "Board meeting",
    #     description: "Discuss plans for the next quarter.",
    #     start: Time.utc(2014, 8, 5, 15, 30),
    #     end:   Time.utc(2014, 8, 5, 17, 30),
    #     location: {
    #       description: "Board room"
    #     })
    #
    # See http://www.cronofy.com/developers/api#upsert-event for reference.
    #
    # Returns nothing.
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::NotFoundError if the calendar does not exist.
    # Raises Cronofy::InvalidRequestError if the request contains invalid
    # parameters.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def upsert_event(calendar_id, event)
      body = event.dup

      body[:start] = encode_event_time(body[:start])
      body[:end] = encode_event_time(body[:end])

      post("/v1/calendars/#{calendar_id}/events", body)
      nil
    end

    # Public: Alias for #upsert_event
    alias_method :create_or_update_event, :upsert_event

    # Public: Returns a lazily-evaluated Enumerable of Events that satisfy the
    # given query criteria.
    #
    # options - The Hash options used to refine the selection (default: {}):
    #           :from            - The minimum Date from which to return events
    #                              (optional).
    #           :to              - The Date to return events up until (optional).
    #           :tzid            - A String representing a known time zone
    #                              identifier from the IANA Time Zone Database
    #                              (default: Etc/UTC).
    #           :include_deleted - A Boolean specifying whether events that have
    #                              been deleted should be included or excluded
    #                              from the results (optional).
    #           :include_moved   - A Boolean specifying whether events that have
    #                              ever existed within the given window should
    #                              be included or excluded from the results
    #                              (optional).
    #           :include_managed - A Boolean specifying whether events that you
    #                              are managing for the account should be
    #                              included or excluded from the results
    #                              (optional).
    #           :only_managed    - A Boolean specifying whether only events that
    #                              you are managing for the account should
    #                              trigger notifications (optional).
    #           :localized_times - A Boolean specifying whether the start and
    #                              end times should be returned with any
    #                              available localization information
    #                              (optional).
    #           :last_modified   - The Time that events must be modified on or
    #                              after in order to be returned (optional).
    #           :calendar_ids    - An Array of calendar ids for restricting the
    #                              returned events (optional).
    #
    # The first page will be retrieved eagerly so that common errors will happen
    # inline. However, subsequent pages (if any) will be requested lazily.
    #
    # See http://www.cronofy.com/developers/api#read-events for reference.
    #
    # Returns a lazily-evaluated Enumerable of Events
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::InvalidRequestError if the request contains invalid
    # parameters.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def read_events(options = {})
      params = READ_EVENTS_DEFAULT_PARAMS.merge(options)

      READ_EVENTS_TIME_PARAMS.select { |tp| params.key?(tp) }.each do |tp|
        params[tp] = to_iso8601(params[tp])
      end

      url = ::Cronofy.api_url + "/v1/events"
      PagedResultIterator.new(PagedEventsResult, :events, access_token!, url, params)
    end

    # Public: Returns a lazily-evaluated Enumerable of FreeBusy that satisfy the
    # given query criteria.
    #
    # options - The Hash options used to refine the selection (default: {}):
    #           :from            - The minimum Date from which to return events
    #                              (optional).
    #           :to              - The Date to return events up until (optional).
    #           :tzid            - A String representing a known time zone
    #                              identifier from the IANA Time Zone Database
    #                              (default: Etc/UTC).
    #           :include_managed - A Boolean specifying whether events that you
    #                              are managing for the account should be
    #                              included or excluded from the results
    #                              (optional).
    #           :localized_times - A Boolean specifying whether the start and
    #                              end times should be returned with any
    #                              available localization information
    #                              (optional).
    #           :calendar_ids    - An Array of calendar ids for restricting the
    #                              returned events (optional).
    #
    # The first page will be retrieved eagerly so that common errors will happen
    # inline. However, subsequent pages (if any) will be requested lazily.
    #
    # See http://www.cronofy.com/developers/api/alpha#free-busy for reference.
    #
    # Returns a lazily-evaluated Enumerable of FreeBusy
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::InvalidRequestError if the request contains invalid
    # parameters.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def free_busy(options = {})
      params = FREE_BUSY_DEFAULT_PARAMS.merge(options)

      FREE_BUSY_TIME_PARAMS.select { |tp| params.key?(tp) }.each do |tp|
        params[tp] = to_iso8601(params[tp])
      end

      url = ::Cronofy.api_url + "/v1/free_busy"
      PagedResultIterator.new(PagedFreeBusyResult, :free_busy, access_token!, url, params)
    end

    # Public: Deletes an event from the specified calendar
    #
    # calendar_id - The String Cronofy ID for the calendar to delete the event
    #               from.
    # event_id    - A String uniquely identifying the event for your application
    #               (note: this is NOT an ID generated by Cronofy).
    #
    # See http://www.cronofy.com/developers/api#delete-event for reference.
    #
    # Returns nothing.
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::NotFoundError if the calendar does not exist.
    # Raises Cronofy::InvalidRequestError if the request contains invalid
    # parameters.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def delete_event(calendar_id, event_id)
      delete("/v1/calendars/#{calendar_id}/events", event_id: event_id)
      nil
    end

    # Public: Deletes all events you are managing for the account.
    #
    # See http://www.cronofy.com/developers/api/alpha#bulk-delete-events for
    # reference.
    #
    # Returns nothing.
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::NotFoundError if the calendar does not exist.
    # Raises Cronofy::InvalidRequestError if the request contains invalid
    # parameters.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def delete_all_events
      delete("/v1/events", delete_all: true)
      nil
    end

    # Public: Creates a notification channel with a callback URL
    #
    # callback_url - A String specifing the callback URL for the channel.
    #
    # See http://www.cronofy.com/developers/api#create-channel for reference.
    #
    # Returns a Channel.
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::InvalidRequestError if the request contains invalid
    # parameters.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def create_channel(callback_url)
      response = post("/v1/channels", callback_url: callback_url)
      parse_json(Channel, "channel", response)
    end

    # Public: Lists all the notification channels for the account.
    #
    # See http://www.cronofy.com/developers/api#list-channels for reference.
    #
    # Returns an Array of Channels.
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def list_channels
      response = get("/v1/channels")
      parse_collection(Channel, "channels", response)
    end

    # Public: Closes a notification channel.
    #
    # channel_id - The String Cronofy ID for the channel to close.
    #
    # See http://www.cronofy.com/developers/api#close-channel for reference.
    #
    # Returns nothing.
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::NotFoundError if the channel does not exist.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def close_channel(channel_id)
      delete("/v1/channels/#{channel_id}")
      nil
    end

    # Public: Retrieves the details of the account.
    #
    # See http://www.cronofy.com/developers/api#account for reference.
    #
    # Returns an Account.
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::AuthorizationFailureError if the access token does not
    # include the required scope.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def account
      response = get("/v1/account")
      parse_json(Account, "account", response)
    end

    # Public: Lists all the profiles for the account.
    #
    # See https://www.cronofy.com/developers/api/alpha/#profiles for reference.
    #
    # Returns an Array of Profiles
    #
    # Raises Cronofy::CredentialsMissingError if no credentials available.
    # Raises Cronofy::AuthenticationFailureError if the access token is no
    # longer valid.
    # Raises Cronofy::TooManyRequestsError if the request exceeds the rate
    # limits for the application.
    def list_profiles
      response = get("/v1/profiles")
      parse_collection(Profile, "profiles", response)
    end

    # Public: Generates a URL to send the user to in order to perform the OAuth
    # 2.0 authorization process.
    #
    # redirect_uri - A String specifing the URI to return the user to once they
    #                have completed the authorization steps.
    # options      - The Hash options used to refine the selection
    #                (default: {}):
    #                :scope - Array of scopes describing the access to request
    #                         from the user to the users calendars
    #                         (default: DEFAULT_OAUTH_SCOPE).
    #                :state - String containing the state value to retain during
    #                         the OAuth authorization process (optional).
    #
    # See http://www.cronofy.com/developers/api#authorization for reference.
    #
    # Returns the URL as a String.
    def user_auth_link(redirect_url, options = {})
      options = { scope: DEFAULT_OAUTH_SCOPE }.merge(options)
      @auth.user_auth_link(redirect_url, options)
    end

    # Public: Retrieves the OAuth credentials authorized for the given code and
    # redirect URL pair.
    #
    # code         - String code returned to redirect_url after authorization.
    # redirect_url - A String specifing the URL the user returned to once they
    #                had completed the authorization steps.
    #
    # See http://www.cronofy.com/developers/api#token-issue for reference.
    #
    # Returns a set of Cronofy::Credentials for the account.
    #
    # Raises Cronofy::BadRequestError if the code is unknown, has been revoked,
    # or the code and redirect URL do not match.
    # Raises Cronofy::AuthenticationFailureError if the client ID and secret are
    # not valid.
    def get_token_from_code(code, redirect_url)
      @auth.get_token_from_code(code, redirect_url)
    end

    # Public: Refreshes the credentials for the account's access token.
    #
    # Usually called in response to a Cronofy::AuthenticationFailureError as
    # these usually occur when the access token has expired and needs
    # refreshing.
    #
    # See http://www.cronofy.com/developers/api#token-refresh for reference.
    #
    # Returns a set of Cronofy::Credentials for the account.
    #
    # Raises Cronofy::BadRequestError if refresh token code is unknown or has
    # been revoked.
    # Raises Cronofy::AuthenticationFailureError if the client ID and secret are
    # not valid.
    def refresh_access_token
      @auth.refresh!
    end

    # Public: Revokes the account's refresh token and access token.
    #
    # After making this call the Client will become unusable. You should also
    # delete the stored credentials used to create this instance.
    #
    # See http://www.cronofy.com/developers/api#revoke-authorization for
    # reference.
    #
    # Returns nothing.
    #
    # Raises Cronofy::AuthenticationFailureError if the client ID and secret are
    # not valid.
    def revoke_authorization
      @auth.revoke!
    end

    private

    FREE_BUSY_DEFAULT_PARAMS = { tzid: "Etc/UTC" }.freeze
    FREE_BUSY_TIME_PARAMS = %i{
      from
      to
    }.freeze

    READ_EVENTS_DEFAULT_PARAMS = { tzid: "Etc/UTC" }.freeze
    READ_EVENTS_TIME_PARAMS = %i{
      from
      to
      last_modified
    }.freeze

    def access_token!
      raise CredentialsMissingError.new unless @auth.access_token
      @auth.access_token
    end

    def get(url, opts = {})
      wrapped_request { access_token!.get(url, opts) }
    end

    def post(url, body)
      wrapped_request { access_token!.post(url, json_request_args(body)) }
    end

    def delete(url, body = nil)
      wrapped_request { access_token!.delete(url, json_request_args(body)) }
    end

    def wrapped_request
      yield
    rescue OAuth2::Error => e
      raise Errors.map_error(e)
    end

    def parse_collection(type, attr, response)
      ResponseParser.new(response).parse_collection(type, attr)
    end

    def parse_json(type, attr = nil, response)
      ResponseParser.new(response).parse_json(type, attr)
    end

    def json_request_args(body_hash)
      if body_hash
        {
          body: JSON.generate(body_hash),
          headers: { "Content-Type" => "application/json; charset=utf-8" },
        }
      else
        {}
      end
    end

    def to_iso8601(value)
      case value
      when NilClass
        nil
      when Time
        value.getutc.iso8601
      else
        value.iso8601
      end
    end

    def encode_event_time(time)
      result = time

      case time
      when Hash
        if time[:time]
          encoded_time = encode_event_time(time[:time])
          time.merge(time: encoded_time)
        else
          time
        end
      else
        to_iso8601(time)
      end
    end

    class PagedResultIterator
      include Enumerable

      def initialize(page_parser, items_key, access_token, url, params)
        @page_parser = page_parser
        @items_key = items_key
        @access_token = access_token
        @url = url
        @params = params
        @first_page = get_page(url, params)
      end

      def each
        page = @first_page

        page[@items_key].each do |item|
          yield item
        end

        while page.pages.next_page?
          page = get_page(page.pages.next_page)

          page[@items_key].each do |item|
            yield item
          end
        end
      end

      private

      attr_reader :access_token
      attr_reader :params
      attr_reader :url

      def get_page(url, params = {})
        response = http_get(url, params)
        parse_page(response)
      end

      def http_get(url, params = {})
        response = Faraday.get(url, params, oauth_headers)
        Errors.raise_if_error(response)
        response
      end

      def oauth_headers
        {
          "Authorization" => "Bearer #{access_token.token}",
          "User-Agent" => "Cronofy Ruby #{::Cronofy::VERSION}",
        }
      end

      def parse_page(response)
        ResponseParser.new(response).parse_json(@page_parser)
      end
    end
  end

  # Deprecated: Alias for Client for backwards compatibility.
  class Cronofy < Client
  end
end
