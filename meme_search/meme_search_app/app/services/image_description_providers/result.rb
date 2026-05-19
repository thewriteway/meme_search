# frozen_string_literal: true

module ImageDescriptionProviders
  Result = Data.define(:success, :message, :queued) do
    def success?
      success
    end

    def queued?
      queued
    end
  end
end
