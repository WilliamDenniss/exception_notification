module ExceptionNotifier
  class MattermostNotifier

    GIT_URL = "git.studio-hb.fr/studio-hb"
    USERNAME = "Exception Notifier"

    attr_accessor :httparty

    def initialize(options = {})
      super()
      @default_options = options
      @httparty = HTTParty
    end

    def call(exception, options = {})
      @options = options.merge(@default_options)
      @exception = exception

      @env = @options.delete(:env)

      @application_name = @options.delete(:app_name) || Rails.application.class.parent_name.underscore
      @gitlab_url = @options.delete(:git_url)
      @username = @options.delete(:username) || USERNAME
      @avatar = @options.delete(:avatar)

      @webhook_url = @options.delete(:webhook_url)
      raise ArgumentError.new "You must provide 'webhook_url' parameter." unless @webhook_url

      unless @env.nil?
        @controller = @env['action_controller.instance'] || MissingController.new

        request = ActionDispatch::Request.new(@env)

        @request_items = { url: request.original_url,
                           http_method: request.method,
                           ip_address: request.remote_ip,
                           parameters: request.filtered_parameters,
                           timestamp: Time.current }

        if request.session["warden.user.user.key"]
          current_user = User.find(request.session["warden.user.user.key"][0][0])
          @request_items.merge!({ current_user: { id: current_user.id, email: current_user.email  } })
        end

      end

      payload = message_text.merge(user_info)

      @options[:body] = payload.to_json
      @options[:headers] ||= {}
      @options[:headers].merge!({ 'Content-Type' => 'application/json' })

      @httparty.post(@webhook_url, @options)
    end

    private

      def user_info
        infos = {}

        infos.merge!({ username: @username }) if @username
        infos.merge!({ icon_url: @avatar }) if @avatar

        infos
      end

      def message_text
        text = []

        text += ["@channel"]
        text += message_header
        text += message_request if @request_items
        text += message_backtrace if @exception.backtrace
        text += message_issue_link if @gitlab_url

        { text: text.join("\n") }
      end

      def message_header
        text = []

        text << "### :warning: Error 500 in #{Rails.env} :warning:"
        text << "An *#{@exception.class}* occured" + if @controller then " in *#{controller_and_method}*." else "." end
        text << "*#{@exception.message}*"

        text
      end

      def message_request
        text = []

        text << "### Request"
        text << "```"
        text << hash_presentation(@request_items)
        text << "```"

        text
      end

      def message_backtrace(size = 3)
        text = []

        text << "### Backtrace"
        text << "```"
        size.times { |i| text << "* " + @exception.backtrace[i] }
        text << "```"

        text
      end

      def message_issue_link
        text = []

        link = [@gitlab_url, @application_name, "issues", "new"].join("/")
        params = {
          "issue[title]" => ["[BUG] Error 500 :",
                                       controller_and_method,
                                       "(#{@exception.class})",
                                       @exception.message].compact.join(" ")
        }.to_query

        text << "[Create an issue](#{link}/?#{params})"

        text
      end

      def controller_and_method
        if @controller
          "#{@controller.controller_name}##{@controller.action_name}"
        else
          ""
        end
      end

      def hash_presentation(hash)
        text = []

        hash.each do |key, value|
          text << "* #{key} : #{value}"
        end

        text.join("\n")
      end

  end
end
