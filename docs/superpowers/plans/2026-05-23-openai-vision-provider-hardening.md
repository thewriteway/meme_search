# OpenAI Vision Provider Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden PR #153 so the OpenAI-compatible description provider handles model output length, avoids long synchronous bulk requests, and has executable verification.

**Architecture:** Keep the provider abstraction introduced by PR #153, but make provider results safe for the existing `ImageCore` validation contract. Move OpenAI bulk generation out of the controller request path by enqueuing one ActiveJob per image, while preserving the local Python provider's existing queue behavior. Add tests around the exact failure modes found in review.

**Tech Stack:** Rails 8, Minitest, WebMock, ActiveJob test adapter, ActionCable, PostgreSQL-backed Rails models, Docker/mise for Ruby 3.4.2 execution.

---

## File Structure

- Modify: `meme_search/meme_search_app/app/services/image_description_providers/result.rb`
  - Replace `Data.define` with a Ruby-version-compatible value object or `Struct`.
  - Keep the public methods `success?` and `queued?`.
- Modify: `meme_search/meme_search_app/app/services/image_description_providers/openai_provider.rb`
  - Add `max_tokens` to the OpenAI request.
  - Normalize generated descriptions before saving.
  - Return a clear failure result when normalized output is blank.
- Create: `meme_search/meme_search_app/app/jobs/generate_image_description_job.rb`
  - Run provider generation asynchronously for one `ImageCore`.
  - Broadcast status updates through existing model/provider flows.
- Modify: `meme_search/meme_search_app/app/controllers/image_cores_controller.rb`
  - Keep single-image generation behavior simple.
  - Change OpenAI bulk generation to enqueue jobs instead of doing network calls in the request.
- Modify: `meme_search/meme_search_app/test/services/image_description_providers_test.rb`
  - Add tests for long OpenAI responses, blank normalized responses, max token request payloads, and `Result` compatibility.
- Create: `meme_search/meme_search_app/test/jobs/generate_image_description_job_test.rb`
  - Test job success and missing-record behavior.
- Modify: `meme_search/meme_search_app/test/controllers/image_cores_controller_test.rb`
  - Add bulk generation tests proving OpenAI mode enqueues jobs and does not call the API inline.
- Modify: `README.md`
  - Document max length behavior and recommended bulk behavior.

---

### Task 1: Make Provider Result Ruby-Compatible

**Files:**
- Modify: `meme_search/meme_search_app/app/services/image_description_providers/result.rb`
- Test: `meme_search/meme_search_app/test/services/image_description_providers_test.rb`

- [ ] **Step 1: Write the failing test**

Append this test inside `ImageDescriptionProvidersTest`:

```ruby
test "result exposes predicate helpers without relying on Ruby Data" do
  result = ImageDescriptionProviders::Result.new(success: true, message: "Queued", queued: true)

  assert result.success?
  assert result.queued?
  assert_equal "Queued", result.message
end
```

- [ ] **Step 2: Run test to verify current behavior**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/services/image_description_providers_test.rb
```

Expected before the fix on Ruby versions without `Data`: failure while loading `ImageDescriptionProviders::Result`, with an error like `uninitialized constant Data`. If running only in Ruby 3.4.2, the test may pass before the fix; still make the implementation change for compatibility with local developer machines.

- [ ] **Step 3: Replace `Data.define` with a small explicit class**

Replace `meme_search/meme_search_app/app/services/image_description_providers/result.rb` with:

```ruby
# frozen_string_literal: true

module ImageDescriptionProviders
  class Result
    attr_reader :message

    def initialize(success:, message:, queued:)
      @success = success
      @message = message
      @queued = queued
    end

    def success?
      @success
    end

    def queued?
      @queued
    end
  end
end
```

- [ ] **Step 4: Run focused test**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/services/image_description_providers_test.rb
```

Expected: provider tests pass or fail only on unrelated existing setup issues.

- [ ] **Step 5: Commit**

```bash
git add meme_search/meme_search_app/app/services/image_description_providers/result.rb meme_search/meme_search_app/test/services/image_description_providers_test.rb
git commit -m "fix: make image description result ruby compatible"
```

---

### Task 2: Bound OpenAI Description Length Before Save

**Files:**
- Modify: `meme_search/meme_search_app/app/services/image_description_providers/openai_provider.rb`
- Test: `meme_search/meme_search_app/test/services/image_description_providers_test.rb`

- [ ] **Step 1: Write failing tests for long and blank normalized output**

Add these tests to `ImageDescriptionProvidersTest`:

```ruby
test "openai provider truncates long descriptions to image validation limit" do
  long_description = "A" * 700

  with_openai_env do
    stub_request(:post, "http://openai.test/v1/chat/completions")
      .to_return(
        status: 200,
        body: { choices: [ { message: { content: long_description } } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    @image_core.stub(:refresh_description_embeddings, true) do
      ActionCable.server.stub(:broadcast, true) do
        result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)

        assert result.success?
      end
    end
  end

  @image_core.reload
  assert_equal 500, @image_core.description.length
  assert_equal "done", @image_core.status
end

test "openai provider fails when normalized description is blank" do
  with_openai_env do
    stub_request(:post, "http://openai.test/v1/chat/completions")
      .to_return(
        status: 200,
        body: { choices: [ { message: { content: "   \n\t   " } } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = ImageDescriptionProviders::OpenaiProvider.new.generate(@image_core)

    assert_not result.success?
    assert_match "unsupported response", result.message
    assert_equal "failed", @image_core.reload.status
  end
end
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/services/image_description_providers_test.rb
```

Expected: long-description test fails because `update!` hits the 500-character validation and the provider returns failure.

- [ ] **Step 3: Add constants and normalization**

In `OpenaiProvider`, add constants near `PROMPT`:

```ruby
MAX_DESCRIPTION_LENGTH = ImageCore.validators_on(:description)
  .grep(ActiveModel::Validations::LengthValidator)
  .filter_map { |validator| validator.options[:maximum] }
  .min || 500
MAX_COMPLETION_TOKENS = 160
```

Change `request_body` to include `max_tokens`:

```ruby
def request_body(image_core)
  {
    model: model,
    max_tokens: MAX_COMPLETION_TOKENS,
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: PROMPT },
          { type: "image_url", image_url: { url: data_uri(image_core) } }
        ]
      }
    ]
  }
end
```

Add this private method:

```ruby
def normalize_description(description)
  description.to_s.squish.truncate(MAX_DESCRIPTION_LENGTH, omission: "")
end
```

Change `generate` to normalize before blank check and save:

```ruby
description = normalize_description(request_description(image_core))
if description.blank?
  return fail_image(image_core, "OpenAI vision API returned an unsupported response.")
end

save_description(image_core, description)
```

- [ ] **Step 4: Add request-payload assertion for `max_tokens`**

Update `openai_request_valid?` in `ImageDescriptionProvidersTest`:

```ruby
def openai_request_valid?(request)
  body = JSON.parse(request.body)
  image_url = body.dig("messages", 0, "content", 1, "image_url", "url")

  request.headers["Authorization"] == "Bearer test-key" &&
    body["model"] == "vision-test" &&
    body["max_tokens"] == 160 &&
    image_url.start_with?("data:image/jpeg;base64,")
end
```

- [ ] **Step 5: Run focused provider tests**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/services/image_description_providers_test.rb
```

Expected: all provider tests pass.

- [ ] **Step 6: Commit**

```bash
git add meme_search/meme_search_app/app/services/image_description_providers/openai_provider.rb meme_search/meme_search_app/test/services/image_description_providers_test.rb
git commit -m "fix: bound openai image descriptions"
```

---

### Task 3: Add Provider Capability API

**Files:**
- Modify: `meme_search/meme_search_app/app/services/image_description_providers/local_provider.rb`
- Modify: `meme_search/meme_search_app/app/services/image_description_providers/openai_provider.rb`
- Test: `meme_search/meme_search_app/test/services/image_description_providers_test.rb`

- [ ] **Step 1: Write tests for provider capabilities**

Add these tests:

```ruby
test "local provider reports asynchronous queue behavior" do
  provider = ImageDescriptionProviders::LocalProvider.new

  assert provider.queued_provider?
  assert_equal "local", provider.name
end

test "openai provider reports inline generation behavior" do
  provider = ImageDescriptionProviders::OpenaiProvider.new

  assert_not provider.queued_provider?
  assert_equal "openai", provider.name
end
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/services/image_description_providers_test.rb
```

Expected: failures for missing `queued_provider?` and `name`.

- [ ] **Step 3: Implement provider capability methods**

Add to `LocalProvider`:

```ruby
def name
  "local"
end

def queued_provider?
  true
end
```

Add to `OpenaiProvider`:

```ruby
def name
  "openai"
end

def queued_provider?
  false
end
```

- [ ] **Step 4: Run focused provider tests**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/services/image_description_providers_test.rb
```

Expected: all provider tests pass.

- [ ] **Step 5: Commit**

```bash
git add meme_search/meme_search_app/app/services/image_description_providers/local_provider.rb meme_search/meme_search_app/app/services/image_description_providers/openai_provider.rb meme_search/meme_search_app/test/services/image_description_providers_test.rb
git commit -m "refactor: expose image description provider capabilities"
```

---

### Task 4: Add Async Job for External Provider Generation

**Files:**
- Create: `meme_search/meme_search_app/app/jobs/generate_image_description_job.rb`
- Create: `meme_search/meme_search_app/test/jobs/generate_image_description_job_test.rb`

- [ ] **Step 1: Write job tests**

Create `meme_search/meme_search_app/test/jobs/generate_image_description_job_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"

class GenerateImageDescriptionJobTest < ActiveJob::TestCase
  test "generates description for an existing image" do
    image_core = image_cores(:one)
    provider = Minitest::Mock.new
    provider.expect(:generate, ImageDescriptionProviders::Result.new(success: true, message: "Generated description.", queued: false), [ image_core ])

    ImageDescriptionProviders::Factory.stub(:build, provider) do
      GenerateImageDescriptionJob.perform_now(image_core.id)
    end

    provider.verify
  end

  test "does nothing when image no longer exists" do
    assert_nothing_raised do
      GenerateImageDescriptionJob.perform_now(-1)
    end
  end
end
```

- [ ] **Step 2: Run job tests to verify failure**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/jobs/generate_image_description_job_test.rb
```

Expected: failure because `GenerateImageDescriptionJob` does not exist.

- [ ] **Step 3: Implement the job**

Create `meme_search/meme_search_app/app/jobs/generate_image_description_job.rb`:

```ruby
# frozen_string_literal: true

class GenerateImageDescriptionJob < ApplicationJob
  queue_as :default

  def perform(image_core_id)
    image_core = ImageCore.find_by(id: image_core_id)
    return unless image_core

    ImageDescriptionProviders::Factory.build.generate(image_core)
  end
end
```

- [ ] **Step 4: Run job tests**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/jobs/generate_image_description_job_test.rb
```

Expected: job tests pass.

- [ ] **Step 5: Commit**

```bash
git add meme_search/meme_search_app/app/jobs/generate_image_description_job.rb meme_search/meme_search_app/test/jobs/generate_image_description_job_test.rb
git commit -m "feat: add async image description generation job"
```

---

### Task 5: Make OpenAI Bulk Generation Enqueue Jobs

**Files:**
- Modify: `meme_search/meme_search_app/app/controllers/image_cores_controller.rb`
- Modify: `meme_search/meme_search_app/test/controllers/image_cores_controller_test.rb`

- [ ] **Step 1: Add controller tests for OpenAI bulk behavior**

Add tests to `ImageCoresControllerTest` near existing bulk generation tests:

```ruby
test "bulk generate descriptions enqueues jobs for openai provider without calling api inline" do
  ImageCore.update_all(description: "already described", status: ImageCore.statuses[:done])
  image_core = image_cores(:one)
  image_core.update!(description: nil, status: :not_started)

  with_env("IMAGE_DESCRIPTION_PROVIDER" => "openai") do
    assert_enqueued_with(job: GenerateImageDescriptionJob, args: [ image_core.id ]) do
      post bulk_generate_descriptions_image_cores_url
    end
  end

  assert_redirected_to image_cores_path
  assert_match "Queued 1 images", flash[:notice]
  assert_equal "in_queue", image_core.reload.status
end
```

If `ImageCoresControllerTest` does not already include a `with_env` helper, add this private helper at the bottom of the test class:

```ruby
def with_env(values)
  old_values = values.keys.to_h { |key| [ key, ENV[key] ] }
  values.each do |key, value|
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
  yield
ensure
  old_values.each do |key, value|
    value.nil? ? ENV.delete(key) : ENV[key] = value
  end
end
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/controllers/image_cores_controller_test.rb
```

Expected: failure because OpenAI bulk currently calls `provider.generate` inline and no job is enqueued.

- [ ] **Step 3: Change bulk generation branching**

In `bulk_generate_descriptions`, replace the loop with:

```ruby
images_without_descriptions.each do |image_core|
  if provider.queued_provider?
    result = provider.generate(image_core)
    if result.success?
      queued_count += 1
    else
      failed_count += 1
    end
  else
    image_core.update(status: :in_queue)
    GenerateImageDescriptionJob.perform_later(image_core.id)
    queued_count += 1
  end
end
```

Remove `generated_count` and the flash text branch for immediately generated descriptions. Keep the existing `session[:bulk_operation]` metadata; the job will update statuses from `in_queue` to `processing`, `done`, or `failed` as it runs.

Use this flash construction:

```ruby
notices = []
notices << "Queued #{queued_count} images for description generation." if queued_count > 0
notices << "No images needed description generation." if notices.empty? && failed_count == 0
flash[:notice] = notices.join(" ")
flash[:alert] = "Failed to queue #{failed_count} images." if failed_count > 0
```

- [ ] **Step 4: Run controller tests**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/controllers/image_cores_controller_test.rb
```

Expected: controller tests pass.

- [ ] **Step 5: Commit**

```bash
git add meme_search/meme_search_app/app/controllers/image_cores_controller.rb meme_search/meme_search_app/test/controllers/image_cores_controller_test.rb
git commit -m "fix: enqueue openai bulk description generation"
```

---

### Task 6: Verify Single-Image OpenAI Behavior Remains Synchronous

**Files:**
- Modify: `meme_search/meme_search_app/test/controllers/image_cores_controller_test.rb`

- [ ] **Step 1: Add single-image controller test**

Add:

```ruby
test "single image generate description runs openai provider immediately" do
  image_core = image_cores(:one)
  image_core.update!(description: nil, status: :not_started)
  result = ImageDescriptionProviders::Result.new(success: true, message: "Generated description.", queued: false)
  provider = Minitest::Mock.new
  provider.expect(:generate, result, [ image_core ])

  with_env("IMAGE_DESCRIPTION_PROVIDER" => "openai") do
    ImageDescriptionProviders::Factory.stub(:build, provider) do
      assert_no_enqueued_jobs do
        post generate_description_image_core_url(image_core)
      end
    end
  end

  assert_redirected_to root_path
  assert_equal "Generated description.", flash[:notice]
  provider.verify
end
```

- [ ] **Step 2: Run controller tests**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test test/controllers/image_cores_controller_test.rb
```

Expected: pass. This locks the intended behavior: bulk is async, single-image generation remains simple and immediate.

- [ ] **Step 3: Commit**

```bash
git add meme_search/meme_search_app/test/controllers/image_cores_controller_test.rb
git commit -m "test: cover single image openai generation"
```

---

### Task 7: Documentation Update

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update provider documentation**

In the `Description generation providers` section, add:

```markdown
OpenAI-compatible descriptions are normalized to the app's description length limit before saving. Bulk generation queues background jobs for external providers so the web request does not wait on one API request per image.
```

- [ ] **Step 2: Run markdown diff check**

Run:

```bash
git diff -- README.md
```

Expected: README only mentions behavior that is implemented by Tasks 2 and 5.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: clarify openai description generation behavior"
```

---

### Task 8: Full Verification

**Files:**
- No new files.

- [ ] **Step 1: Run focused Rails tests**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bin/rails test \
  test/services/image_description_providers_test.rb \
  test/jobs/generate_image_description_job_test.rb \
  test/controllers/image_cores_controller_test.rb
```

Expected: all focused Rails tests pass.

- [ ] **Step 2: Run Rails test suite if time allows**

Run:

```bash
cd meme_search/meme_search_app
mise exec -- bash run_tests.sh
```

Expected: Rails test suite passes.

- [ ] **Step 3: Run diff and whitespace checks**

Run:

```bash
git diff --check main...HEAD
git status --short
```

Expected: no whitespace errors. `git status --short` should only show intentional uncommitted changes if this plan is being executed without per-task commits.

- [ ] **Step 4: Inspect final PR diff**

Run:

```bash
git diff --stat main...HEAD
git diff main...HEAD -- meme_search/meme_search_app/app/services/image_description_providers/openai_provider.rb
git diff main...HEAD -- meme_search/meme_search_app/app/controllers/image_cores_controller.rb
```

Expected: final diff shows bounded OpenAI output, async OpenAI bulk behavior, provider capability methods, and focused tests.

---

## Self-Review

- Spec coverage: The plan addresses all review findings: description validation failure, synchronous bulk OpenAI calls, no executable checks, and Ruby `Data.define` compatibility risk.
- Placeholder scan: No implementation task uses TBD/TODO placeholders; each code-changing task includes concrete snippets and commands.
- Type consistency: `ImageDescriptionProviders::Result.new(success:, message:, queued:)`, `success?`, `queued?`, `provider.name`, and `provider.queued_provider?` are defined before later tasks depend on them.
