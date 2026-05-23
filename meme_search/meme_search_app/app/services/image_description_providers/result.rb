# frozen_string_literal: true

module ImageDescriptionProviders
  class Result
    attr_reader :success, :message, :queued

    def initialize(success:, message:, queued:)
      @success = success
      @message = message
      @queued = queued
    end

    def success?
      success
    end

    def queued?
      queued
    end
  end
end
