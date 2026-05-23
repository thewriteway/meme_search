# frozen_string_literal: true

require "test_helper"

class ActiveJobQueueConfigurationTest < ActiveSupport::TestCase
  test "application uses durable Solid Queue adapter" do
    assert_equal :solid_queue, Rails.application.config.active_job.queue_adapter
  end
end
