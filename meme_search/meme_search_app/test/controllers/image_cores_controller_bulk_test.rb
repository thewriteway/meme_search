# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require_relative "concerns/bulk_generation_test_helpers"

class ImageCoresControllerBulkTest < ActionDispatch::IntegrationTest
  include BulkGenerationTestHelpers

  def setup
    # Clear all dynamic test data to ensure test isolation
    # Delete in correct order due to foreign key constraints
    ImageEmbedding.delete_all  # Child first
    ImageTag.delete_all  # Child first
    ImageCore.delete_all  # Parent after children
    ImageDescriptionBulkOperation.delete_all
    # Keep fixture data, delete only test-created data
    TagName.where("name LIKE 'tag_%' OR name LIKE 'special%' OR name LIKE 'bulk_%'").delete_all
    ImagePath.where("name LIKE 'test_%' OR name LIKE 'special%'").delete_all

    @image_path = image_paths(:one)
    @image_to_text = image_to_texts(:one)
    @image_to_text.update!(current: true)

    # Create test directories for ImagePath validation
    @test_dir_2 = "test_path_2"
    @test_dir_special = "special_path"
    FileUtils.mkdir_p(Rails.root.join("public/memes/#{@test_dir_2}"))
    FileUtils.mkdir_p(Rails.root.join("public/memes/#{@test_dir_special}"))
  end

  def teardown
    # Clean up test directories
    FileUtils.rm_rf(Rails.root.join("public/memes/#{@test_dir_2}")) if @test_dir_2
    FileUtils.rm_rf(Rails.root.join("public/memes/#{@test_dir_special}")) if @test_dir_special
  end

  # =============================================================================
  # PHASE 1: Core Functionality Tests
  # =============================================================================

  # Test 1.1: Basic queuing functionality
  test "bulk_generate_descriptions should queue all images without descriptions" do
    # Setup: Create 3 images without descriptions, 2 with descriptions
    images_without_desc = setup_bulk_test_images(count: 3, with_descriptions: false)
    images_with_desc = setup_bulk_test_images(count: 2, with_descriptions: true, status: 3)

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end

    # Assert redirects
    assert_redirected_to image_cores_path

    operation = current_bulk_operation
    assert_bulk_operation_structure(operation)

    assert_equal 3, operation.total_count
    assert_equal 3, operation_image_ids(operation).length

    # Assert image_ids match the queued images
    queued_ids = images_without_desc.map(&:id)
    assert_equal queued_ids.sort, operation_image_ids(operation).sort

    # Assert only 3 images were queued
    images_without_desc.each do |img|
      assert_image_queued(img)
    end

    # Assert images with descriptions were NOT queued
    images_with_desc.each do |img|
      img.reload
      assert_equal "done", img.status, "Should still be done"
    end
  end

  # Test 1.2: Durable operation data types (critical for bug prevention!)
  test "bulk_generate_descriptions should initialize operation with correct data types" do
    setup_bulk_test_images(count: 2, with_descriptions: false)

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end

    operation = current_bulk_operation
    total_count = operation.total_count
    started_at = operation.started_at.to_i
    image_ids = operation_image_ids(operation)
    filter_params = operation.filter_params

    # Verify data types
    assert_instance_of Integer, total_count, "total_count should be Integer not nil!"
    assert_instance_of Integer, started_at, "started_at should be Integer not nil!"
    assert_instance_of Array, image_ids, "image_ids should be Array"
    assert_instance_of Hash, filter_params, "filter_params should be Hash"

    # Verify values are not nil (critical!)
    assert_not_nil total_count, "total_count must not be nil"
    assert_not_nil started_at, "started_at must not be nil"
    assert_not_nil image_ids, "image_ids must not be nil"
  end

  # Test 1.3: Image IDs tracking for progress bar
  test "bulk_generate_descriptions should store image ids in operation attempts for progress tracking" do
    # Create 4 specific images
    images = setup_bulk_test_images(count: 4, with_descriptions: false)

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end

    operation = current_bulk_operation

    # Assert image_ids contains exactly 4 IDs
    assert_equal 4, operation_image_ids(operation).length

    # Assert IDs match the created test images
    expected_ids = images.map(&:id).sort
    actual_ids = operation_image_ids(operation).sort
    assert_equal expected_ids, actual_ids

    # This test validates the fix for the progress bar bug!
  end

  # Test 1.4: Zero images without descriptions
  test "bulk_generate_descriptions should handle zero images without descriptions" do
    # All images have descriptions
    setup_bulk_test_images(count: 3, with_descriptions: true, status: 3)

    # No HTTP mocking needed - should not make any requests

    post bulk_generate_descriptions_image_cores_url

    # Should still redirect
    assert_redirected_to image_cores_path

    operation = current_bulk_operation
    assert_equal 0, operation.total_count
    assert_equal [], operation_image_ids(operation)
  end

  # Test 1.5: Nil vs empty string descriptions
  test "bulk_generate_descriptions should handle nil vs empty string descriptions" do
    # 2 images with nil description
    images_nil = setup_bulk_test_images(count: 2, with_descriptions: false)

    # 2 images with empty string description
    images_empty = []
    2.times do |i|
      img = ImageCore.create!(
        name: "empty_desc_#{i}.jpg",
        image_path: @image_path,
        status: 0,
        description: ""
      )
      images_empty << img
    end

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end

    # Should queue all 4 images (both nil and "" count as "no description")
    operation = current_bulk_operation
    assert_equal 4, operation.total_count

    # All 4 should be queued
    (images_nil + images_empty).each do |img|
      assert_image_queued(img)
    end
  end

  # Test 1.6: Status 0 images even with descriptions
  test "bulk_generate_descriptions should include status 0 images even with descriptions" do
    # Image with status 0 but has description (unusual but possible)
    img = ImageCore.create!(
      name: "status_0_with_desc.jpg",
      image_path: @image_path,
      status: 0,
      description: "Has description but status is 0"
    )

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end

    # Should be queued (status=0 takes precedence per OR logic)
    operation = current_bulk_operation
    assert_equal 1, operation.total_count
    assert_includes operation_image_ids(operation), img.id
    assert_image_queued(img)
  end

  # =============================================================================
  # PHASE 2: Filter Handling Tests
  # =============================================================================

  # Test 2.1: Tag filter
  test "bulk_generate_descriptions should respect tag filter when queuing images" do
    # Create tags
    tag_1 = TagName.create!(name: "tag_1", color: "#FF0000")
    tag_2 = TagName.create!(name: "tag_2", color: "#00FF00")

    # 3 images with tag_1
    images_tag_1 = setup_bulk_test_images(count: 3, tag_names: [ "tag_1" ])

    # 2 images with tag_2
    images_tag_2 = setup_bulk_test_images(count: 2, tag_names: [ "tag_2" ])

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url, params: { selected_tag_names: "tag_1" }
    end

    operation = current_bulk_operation

    # Should only queue 3 images with tag_1
    assert_equal 3, operation.total_count
    assert_equal 3, operation_image_ids(operation).length

    # Verify correct images queued
    tag_1_ids = images_tag_1.map(&:id).sort
    assert_equal tag_1_ids, operation_image_ids(operation).sort

    # Verify filter params stored
    assert_equal "tag_1", operation.filter_params["selected_tag_names"]
  end

  # Test 2.2: Path filter
  test "bulk_generate_descriptions should respect path filter when queuing images" do
    # Create second path
    path_2 = ImagePath.create!(name: "test_path_2")

    # 2 images in path_1
    images_path_1 = setup_bulk_test_images(count: 2, path_name: @image_path.name)

    # 3 images in path_2
    images_path_2 = setup_bulk_test_images(count: 3, path_name: path_2.name)

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url, params: { selected_path_names: @image_path.name }
    end

    operation = current_bulk_operation

    # Should only queue 2 images from path_1
    assert_equal 2, operation.total_count

    path_1_ids = images_path_1.map(&:id).sort
    assert_equal path_1_ids, operation_image_ids(operation).sort
  end

  # Test 2.3: has_embeddings filter (value "0" = no embeddings)
  test "bulk_generate_descriptions should respect has_embeddings=0 filter" do
    # 3 images without embeddings
    images_no_emb = setup_bulk_test_images(count: 3)

    # 2 images with embeddings
    images_with_emb = setup_bulk_test_images(count: 2)
    images_with_emb.each do |img|
      ImageEmbedding.create!(
        image_core: img,
        embedding: Array.new(384, 0.0),
        snippet: "test embedding snippet"
      )
    end

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url, params: { has_embeddings: "0" }
    end

    operation = current_bulk_operation

    # Should only queue 3 images without embeddings
    assert_equal 3, operation.total_count

    no_emb_ids = images_no_emb.map(&:id).sort
    assert_equal no_emb_ids, operation_image_ids(operation).sort
  end

  # Test 2.4: Empty string has_embeddings should not filter (bug fix validation!)
  test "bulk_generate_descriptions should handle empty string has_embeddings as no filter" do
    # 3 images with embeddings
    images_with_emb = setup_bulk_test_images(count: 3)
    images_with_emb.each do |img|
      ImageEmbedding.create!(image_core: img, embedding: Array.new(384, 0.0), snippet: "test embedding snippet")
    end

    # 2 images without embeddings
    images_no_emb = setup_bulk_test_images(count: 2)

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url, params: { has_embeddings: "" }
    end

    operation = current_bulk_operation

    # Should queue all 5 images (no filter applied for empty string)
    assert_equal 5, operation.total_count

    # This validates the bug fix from lines 432-447!
  end

  # Test 2.5: Combined filters
  test "bulk_generate_descriptions should combine multiple filters correctly" do
    tag = TagName.create!(name: "special_tag", color: "#FF00FF")
    path_2 = ImagePath.create!(name: "special_path")

    # Image matching all criteria: tag + path + no embeddings
    match_img = ImageCore.create!(
      name: "match.jpg",
      image_path: path_2,
      status: 0,
      description: nil
    )
    ImageTag.create!(image_core: match_img, tag_name: tag)

    # Image with tag but wrong path
    wrong_path_img = ImageCore.create!(
      name: "wrong_path.jpg",
      image_path: @image_path,
      status: 0,
      description: nil
    )
    ImageTag.create!(image_core: wrong_path_img, tag_name: tag)

    # Image with path but no tag
    no_tag_img = ImageCore.create!(
      name: "no_tag.jpg",
      image_path: path_2,
      status: 0,
      description: nil
    )

    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url, params: {
        selected_tag_names: "special_tag",
        selected_path_names: "special_path"
      }
    end

    operation = current_bulk_operation

    # Should only queue the one image matching ALL criteria
    assert_equal 1, operation.total_count
    assert_equal [ match_img.id ], operation_image_ids(operation)
  end

  # =============================================================================
  # PHASE 3: bulk_operation_status Tests
  # =============================================================================

  # Test 3.1: Return status when operation exists
  test "bulk_operation_status should return status when operation exists" do
    # Create images WITHOUT descriptions so they'll be queued
    images = setup_bulk_test_images(count: 3, with_descriptions: false)

    # POST to bulk_generate_descriptions to create durable operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end
    assert_redirected_to image_cores_path

    # Now GET status - operation should exist from the POST
    get bulk_operation_status_image_cores_url, as: :json

    assert_response :success

    data = parse_status_response(response)
    assert_equal 3, data["total"]
    assert_not_nil data["status_counts"]
    assert_not_nil data["is_complete"]
    assert_not_nil data["started_at"]
  end

  # Test 3.2: Started-at and total values are durable
  test "bulk_operation_status should return durable total and started_at values" do
    # Create images WITHOUT descriptions so they'll be queued
    images = setup_bulk_test_images(count: 2, with_descriptions: false)

    # POST to bulk_generate_descriptions to create durable operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end
    assert_redirected_to image_cores_path

    # Then make the actual request
    get bulk_operation_status_image_cores_url, as: :json

    assert_response :success

    data = parse_status_response(response)

    # Total should NOT be nil (this was the bug!)
    assert_not_nil data["total"], "total must not be nil - bug fix validation"
    assert_equal 2, data["total"]

    # started_at should NOT be nil
    assert_not_nil data["started_at"], "started_at must not be nil - bug fix validation"
  end

  # Test 3.3: Return error when no active operation exists
  test "bulk_operation_status should return error when no active operation exists" do
    get bulk_operation_status_image_cores_url, as: :json

    assert_response :not_found

    data = parse_status_response(response)
    assert_includes data["error"], "No bulk operation"
  end

  # Test 3.4: Count only images attached to the operation
  test "bulk_operation_status should count only images attached to the operation" do
    # Create images WITHOUT descriptions (will be queued)
    operation_images = setup_bulk_test_images(count: 3, with_descriptions: false)

    # Create image NOT in operation (should NOT be counted)
    # This image gets created and won't be queued in bulk operation
    outside_img = setup_bulk_test_images(count: 1, with_descriptions: true, status: 3).first

    # POST to bulk_generate_descriptions - this queues operation_images
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end
    assert_redirected_to image_cores_path

    # Now update the operation images to different statuses
    operation_images[0].update!(status: 3) # done
    operation_images[1].update!(status: 2) # processing
    operation_images[2].update!(status: 1) # in_queue

    # Get status
    get bulk_operation_status_image_cores_url, as: :json

    assert_response :success

    data = parse_status_response(response)
    status_counts = data["status_counts"]

    # Should count only the 3 images in operation, NOT the outside image!
    assert_equal 1, status_counts["done"], "Only image 1, NOT the outside image!"
    assert_equal 1, status_counts["processing"]
    assert_equal 1, status_counts["in_queue"]
    assert_equal 0, status_counts["failed"]

    # This validates the progress bar fix!
  end

  # Test 3.5: Calculate is_complete correctly
  test "bulk_operation_status should calculate is_complete=true when all done/failed" do
    # Create images WITHOUT descriptions (will be queued)
    images = setup_bulk_test_images(count: 3, with_descriptions: false)

    # POST to bulk_generate_descriptions - this queues images and creates durable operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end
    assert_redirected_to image_cores_path

    # Update images to terminal states
    images[0].update!(status: 3) # done
    images[1].update!(status: 3) # done
    images[2].update!(status: 5) # failed

    # Get status
    get bulk_operation_status_image_cores_url, as: :json

    data = parse_status_response(response)
    assert_equal true, data["is_complete"]
  end

  # Test 3.6: Not complete with active images
  test "bulk_operation_status should set is_complete=false with active images" do
    # Create images WITHOUT descriptions (will be queued)
    images = setup_bulk_test_images(count: 4, with_descriptions: false)

    # POST to bulk_generate_descriptions - this queues images and creates durable operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end
    assert_redirected_to image_cores_path

    # Update images to mixed statuses
    images[0].update!(status: 3) # done
    images[1].update!(status: 3) # done
    images[2].update!(status: 2) # processing - active!
    images[3].update!(status: 1) # in_queue - active!

    # Get status
    get bulk_operation_status_image_cores_url, as: :json

    data = parse_status_response(response)
    assert_equal false, data["is_complete"], "Should not be complete with active images"
  end

  # Test 3.7: Complete operation when all work is finished
  test "bulk_operation_status should mark operation complete when operation complete" do
    # Create images without descriptions
    images = setup_bulk_test_images(count: 2, with_descriptions: false)

    # POST to create durable operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end

    # Mark all images as done
    images.each { |img| img.update!(status: "done") }

    operation = current_bulk_operation

    # GET status - should complete operation since all done
    get bulk_operation_status_image_cores_url, as: :json

    data = parse_status_response(response)
    assert_equal true, data["is_complete"]

    assert_equal "completed", operation.reload.status
    assert_nil ImageDescriptionBulkOperation.current
  end

  # Test 3.8: Keep operation active when incomplete
  test "bulk_operation_status should keep operation active when incomplete" do
    # Create images WITHOUT descriptions (will be queued)
    images = setup_bulk_test_images(count: 2, with_descriptions: false)

    # POST to bulk_generate_descriptions - this queues images and creates durable operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end
    assert_redirected_to image_cores_path

    # Update images to mixed statuses
    images[0].update!(status: 3) # done
    images[1].update!(status: 1) # in_queue - still active!

    # Get status
    get bulk_operation_status_image_cores_url, as: :json

    data = parse_status_response(response)
    assert_equal false, data["is_complete"]

    assert_equal "active", current_bulk_operation.status
  end

  # =============================================================================
  # PHASE 4: bulk_operation_cancel Tests
  # =============================================================================

  # Test 4.1: Cancel pending jobs
  test "bulk_operation_cancel should cancel jobs and mark operation canceled" do
    # Create images WITHOUT descriptions (will be queued)
    images = setup_bulk_test_images(count: 3, with_descriptions: false)

    # POST to bulk_generate_descriptions - this queues images and creates durable operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end
    assert_redirected_to image_cores_path

    operation = current_bulk_operation
    assert_equal "active", operation.status

    # Cancel the operation
    mock_python_service_success do
      post bulk_operation_cancel_image_cores_url, as: :json
    end

    assert_response :success

    data = parse_status_response(response)
    assert_equal 3, data["cancelled_count"]

    assert_equal "canceled", operation.reload.status
    assert_nil ImageDescriptionBulkOperation.current
  end

  test "bulk_operation_cancel should cancel openai jobs locally" do
    images = setup_bulk_test_images(count: 2, with_descriptions: false)

    bulk_provider = Minitest::Mock.new
    bulk_provider.expect(:queued_provider?, false)
    bulk_provider.expect(:queued_provider?, false)
    bulk_provider.expect(:queued_provider?, false)

    ImageDescriptionProviders::Factory.stub(:build, bulk_provider) do
      post bulk_generate_descriptions_image_cores_url
    end

    assert_redirected_to image_cores_path
    bulk_provider.verify
    operation = current_bulk_operation
    unrelated_image = setup_bulk_test_images(count: 1, with_descriptions: false).first
    unrelated_image.update!(status: :in_queue)

    cancel_provider = Object.new
    cancel_provider.define_singleton_method(:queued_provider?) do
      flunk "cancel should use the provider mode captured in the durable bulk operation"
    end

    ImageDescriptionProviders::Factory.stub(:build, cancel_provider) do
      post bulk_operation_cancel_image_cores_url, as: :json
    end

    assert_response :success
    data = parse_status_response(response)
    assert_equal 2, data["cancelled_count"]
    images.each do |image|
      assert_equal "not_started", image.reload.status
    end
    assert_equal "in_queue", unrelated_image.reload.status
    assert_equal "canceled", operation.reload.status
    assert_nil current_bulk_operation
  end

  # Test 4.2: Handle no active operation
  test "bulk_operation_cancel should handle no active operation gracefully" do
    post bulk_operation_cancel_image_cores_url, as: :json

    assert_response :not_found

    data = parse_status_response(response)
    assert_includes data["error"], "No bulk operation"
  end

  # =============================================================================
  # PHASE 5: Integration Tests
  # =============================================================================

  # Test 5.1: Full workflow - generate, poll, complete
  test "full workflow: generate, poll status, complete" do
    images = setup_bulk_test_images(count: 2)

    # Step 1: Start bulk operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end
    assert_redirected_to image_cores_path

    # Step 2: Poll status (should show in progress)
    get bulk_operation_status_image_cores_url, as: :json
    data = parse_status_response(response)
    assert_equal false, data["is_complete"]
    assert_equal 2, data["total"]

    # Step 3: Manually complete images
    images.each { |img| img.update!(status: 3, description: "Done") }

    operation = current_bulk_operation

    # Step 4: Poll again (should show complete and mark operation complete)
    get bulk_operation_status_image_cores_url, as: :json
    data = parse_status_response(response)
    assert_equal true, data["is_complete"]
    assert_equal "completed", operation.reload.status
    assert_nil current_bulk_operation
  end

  # Test 5.2: Full workflow - generate, poll, cancel
  test "full workflow: generate, poll, cancel" do
    images = setup_bulk_test_images(count: 3)

    # Step 1: Start bulk operation
    mock_python_service_success do
      post bulk_generate_descriptions_image_cores_url
    end

    # Step 2: Verify operation active
    get bulk_operation_status_image_cores_url, as: :json
    data = parse_status_response(response)
    assert_equal 3, data["total"]

    # Step 3: Cancel operation
    mock_python_service_success do
      post bulk_operation_cancel_image_cores_url, as: :json
    end

    # Step 4: Verify operation is no longer active
    get bulk_operation_status_image_cores_url, as: :json
    assert_response :not_found
  end
end
