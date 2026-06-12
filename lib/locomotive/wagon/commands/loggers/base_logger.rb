module Locomotive::Wagon

  class BaseLogger

    # drop this logger's global subscriptions; otherwise a second command in the same
    # process would double every log line
    def detach
      (@subscribers || []).each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }
      @subscribers = []
    end

    private

    def log(message, color = nil, ident = nil, print = false)
      ident = ' ' * (ident || 0)

      message = "#{ident}#{message.gsub("\n", "\n" + ident)}"
      message = message.colorize(color) if color

      if print
        print message
      else
        puts message
      end
    end

    def _subscribe(type, action = nil, &block)
      name = ['wagon', type, [*action]].flatten.compact.join('.')

      subscriber = ActiveSupport::Notifications.subscribe(name) do |*args|
        event = ActiveSupport::Notifications::Event.new *args
        yield(event)
      end

      (@subscribers ||= []) << subscriber
    end

  end

end
