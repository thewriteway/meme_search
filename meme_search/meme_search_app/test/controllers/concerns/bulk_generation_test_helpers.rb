# frozen_string_literal: true

module BulkGenerationTestHelpers
  # Create test images for bulk generation testing
  def setup_bulk_test_images(count: 3, with_descriptions: false, status: 0, path_name: nil, tag_names: [])
    images = []
    count.times do |i|
      path = path_name ? ImagePath.find_by(name: path_name) : image_paths(:one)

      image = ImageCore.create!(
        name: "bulk_test_#{i}_#{Time.current.to_i}.jpg",
        image_path: path,
        status: status,
        description: with_descriptions ? "Test description #{i}" : nil
      )

      # Add tags if specified
      tag_names.each do |tag_name|
        tag = TagName.find_or_create_by!(name: tag_name)
        ImageTag.create!(image_core: image, tag_name: tag)
      end

      images << image
    end
    images
  end

  # Mock successful HTTP requests to Python service
  def mock_python_service_success
    stub_request(:post, %r{http://image_to_text_generator:8000/add_job})
      .to_return(status: 200, body: '{"status": "queued"}', headers: { "Content-Type" => "application/json" })
    stub_request(:post, %r{http://image_to_text_generator:8000/remove_job})
      .to_return(status: 200, body: '{"status": "cancelled"}', headers: { "Content-Type" => "application/json" })
    stub_request(:delete, %r{http://image_to_text_generator:8000/remove_job/\d+})
      .to_return(status: 200, body: '{"status": "cancelled"}', headers: { "Content-Type" => "application/json" })
    yield
    WebMock.reset!
  end

  # Mock failed HTTP requests to Python service
  def mock_python_service_failure
    stub_request(:post, %r{http://image_to_text_generator:8000/add_job})
      .to_return(status: 503, body: '{"error": "Service unavailable"}', headers: { "Content-Type" => "application/json" })
    yield
    WebMock.reset!
  end

  # Mock connection error to Python service
  def mock_python_service_connection_error
    stub_request(:post, %r{http://image_to_text_generator:8000/add_job})
      .to_raise(Errno::ECONNREFUSED)
    yield
    WebMock.reset!
  end

  def current_bulk_operation
    ImageDescriptionBulkOperation.current
  end

  def operation_image_ids(operation)
    operation.image_cores.pluck(:id)
  end

  def assert_bulk_operation_structure(operation)
    assert_not_nil operation, "Bulk operation should exist"
    assert_instance_of ImageDescriptionBulkOperation, operation
    assert_instance_of Integer, operation.total_count
    assert_instance_of ActiveSupport::TimeWithZone, operation.started_at
    assert_instance_of Hash, operation.filter_params
  end

  def assert_image_queued(image_core)
    image_core.reload
    assert_equal "in_queue", image_core.status, "Image should be in_queue"
  end

  # Verify image status is done
  def assert_image_done(image_core)
    image_core.reload
    assert_equal "done", image_core.status, "Image should be done"
  end

  # Get status counts from response JSON
  def parse_status_response(response)
    JSON.parse(response.body)
  end

  # Verify status counts match expected values
  def assert_status_counts(response, expected)
    data = parse_status_response(response)
    status_counts = data["status_counts"]

    expected.each do |key, value|
      assert_equal value, status_counts[key.to_s], "#{key} count mismatch"
    end
  end

  private

  def successful_http_response
    Net::HTTPSuccess.new("1.1", "200", "OK").tap do |response|
      response.define_singleton_method(:body) { '{"status": "queued"}' }
    end
  end

  def failed_http_response
    Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable").tap do |response|
      response.define_singleton_method(:body) { '{"error": "Service unavailable"}' }
    end
  end
end
