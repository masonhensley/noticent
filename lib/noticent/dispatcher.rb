# frozen_string_literal: true

module Noticent
  class Dispatcher

    def initialize(config, alert_name, payload, context = {})
      @config = config
      @alert_name = alert_name
      @payload = payload
      @context = context

      validate!
    end

    def alert
      @config.alerts[@alert_name]
    end

    def scope
      alert.scope
    end

    def notifiers
      alert.notifiers
    end

    # returns all recipients of a certain notifier unfiltered regardless of "opt-in" and duplicates
    def recipients(notifier_name)
      scope_object = scope.instance
      raise Noticent::InvalidScope, "scope '#{scope.name}' (#{scope.klass}) doesn't have a #{notifier_name} method" unless scope_object.respond_to? notifier_name
      raise Noticent::BadConfiguration, "scope '#{scope.name}' (#{scope.klass}) method #{notifier_name} should have 1 parameter: payload" unless scope_object.method(notifier_name).arity == 1

      scope_object.send(notifier_name, @payload)
    end

    # only returns recipients that have opted-in for this channel
    def filter_recipients(recipients, channel)
      raise ArgumentError, 'channel should be a string or symbol' unless channel.is_a?(String) || channel.is_a?(Symbol)

      recipients.select { |recipient| Noticent.opt_in_provider.opted_in?(scope: scope.name, entity_id: recipient.id, alert_name: alert.name, channel_name: channel) }
    end

    def dispatch
      notifiers.values.each do |notifier|
        recs = recipients(notifier.recipient)
        @config.channels_by_group(notifier.channel_group).each do |channel|
          to_send = filter_recipients(recs, channel.name)
          channel_instance = channel.instance(to_send, @payload, @context)
          begin
            raise Noticent::BadConfiguration, "channel #{channel.name} (#{channel.klass}) doesn't have a method called #{alert.name}" unless channel_instance.respond_to? alert.name

            channel_instance.send(alert.name)
          rescue => e
            # log and move on
            raise if Noticent.halt_on_error

            Noticent.logger.error e
          end
        end
      end
    end


    private

    def validate!
      raise Noticent::BadConfiguration, 'no base_dir defined' if Noticent.base_dir.nil?
      raise Noticent::MissingConfiguration if @config.nil?
      raise Noticent::BadConfiguration if @config.alerts.nil?
      raise Noticent::InvalidAlert, "no alert #{@alert_name} found" if @config.alerts[@alert_name].nil?
      raise ::ArgumentError, 'payload is nil' if @payload.nil?
      raise ::ArgumentError, 'alert is not a symbol' unless @alert_name.is_a?(Symbol)
    end

  end
end