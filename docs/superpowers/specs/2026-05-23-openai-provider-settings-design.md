# OpenAI Provider Settings UX Design

## Goal

Extend the existing Rails settings Models page so Meme Search can be configured for either local image-description generation or an OpenAI-compatible cloud provider.

The page should keep local generation as the default and primary experience, while making OpenAI setup understandable and testable from the UI.

## Current Context

The current Models settings page is server-rendered Rails/ERB. It uses:

- `settings/shared/tabs` for settings navigation.
- A gradient `AI Models` page heading.
- Glassy rounded cards for local `ImageToText` model rows.
- Toggle-style selection for the active local model.
- A single `Save Selection` action.

The OpenAI provider added in the current PR is configured through environment variables only:

- `IMAGE_DESCRIPTION_PROVIDER`
- `OPENAI_API_BASE_URL`
- `OPENAI_API_KEY`
- `OPENAI_VISION_MODEL`

The new UX must preserve environment-variable support and should not replace the local model page with a generic form.

## Product Decisions

- Provider mode is application-wide.
- Only one provider mode can be active at a time.
- Local generation remains the default and primary path.
- Provider selection uses tabs inside the Models page:
  - `Local generator`
  - `OpenAI-compatible API`
- The Local tab keeps the existing local model card selection pattern.
- There is no redundant local-model dropdown.
- The Cloud tab uses a fixed OpenAI model dropdown for now.
- The saved API key is application-wide.
- `OPENAI_API_KEY` environment variable takes precedence over the saved UI key.
- Existing OpenAI-related environment variables remain supported as deployment overrides.
- The saved API key is never displayed in full.

## UX Structure

The Models page keeps its existing settings shell:

- Existing app nav.
- Existing settings tabs.
- Existing `AI Models` heading style.
- Existing card, badge, toggle, and button language.

Inside the page, add a provider tab container:

### Local Generator Tab

This tab is the default and mirrors the current page.

It shows:

- Intro copy explaining that local generation uses the bundled generator service.
- Existing local model cards from `ImageToText`.
- Existing active model badge/toggle behavior.
- `Save Local Selection` action.

Selecting and saving a local model sets:

- Active provider: `local`.
- Active local model: selected `ImageToText`.

### OpenAI-Compatible API Tab

This tab configures the external provider.

It shows:

- Base URL input, default `https://api.openai.com/v1`.
- Fixed model dropdown:
  - `gpt-4o-mini`
  - `gpt-4.1-mini`
  - `gpt-4.1`
- Password-style API key input for replacing the saved key.
- Key status:
  - `Env key detected`
  - `Saved key ready`
  - `Key missing`
- Runtime key status:
  - `Environment`
  - `Saved key`
  - `Missing`
- Saved key status:
  - redacted form, e.g. `sk-...7a4c`
  - `Not saved`
- Last test status:
  - `Passed`
  - `Failed`
  - `Not tested`
- Environment override status when `IMAGE_DESCRIPTION_PROVIDER`, `OPENAI_API_BASE_URL`, or `OPENAI_VISION_MODEL` is setting runtime behavior.

Actions:

- `Test connection`
- `Save Cloud Selection`
- `Clear saved key`

Saving cloud selection sets:

- Active provider: `openai`.
- OpenAI base URL.
- OpenAI model.
- Optional encrypted saved key, if a new key was entered.

## Runtime Resolution

Provider selection:

1. Use `IMAGE_DESCRIPTION_PROVIDER` when present.
2. Otherwise use the saved application-wide provider setting.
3. If no setting exists, default to `local`.

When `IMAGE_DESCRIPTION_PROVIDER` is present, the UI should explain that runtime provider selection is managed by the environment. Saving UI settings can still update the stored application setting, but it will not affect runtime behavior until the environment override is removed.

OpenAI key resolution:

1. Use `OPENAI_API_KEY` when present.
2. Otherwise use the encrypted saved API key.
3. Otherwise fail generation with a setup-required message.

OpenAI model and base URL resolution:

1. Use environment variables when present:
   - `OPENAI_API_BASE_URL`
   - `OPENAI_VISION_MODEL`
2. Otherwise use saved UI settings.
3. Otherwise use defaults:
   - base URL: `https://api.openai.com/v1`
   - model: `gpt-4o-mini`

When base URL or model environment variables are present, the UI should show that those fields are environment-managed for runtime. Saved UI values can still be edited for later use, but runtime uses the environment values until the overrides are removed.

## Data Model

Add an application-wide settings record, for example `DescriptionProviderSetting`.

Suggested fields:

- `provider`, enum/string: `local`, `openai`
- `openai_base_url`, string
- `openai_model`, string
- encrypted `openai_api_key`
- `openai_key_last_four`, string
- `openai_last_test_status`, string
- `openai_last_tested_at`, datetime
- `openai_last_test_error`, string/text

Only one active settings record should exist. This can be enforced through a singleton accessor rather than user-facing CRUD.

## Security

- Do not render the full saved API key after save.
- Do not log API key values.
- Do not include API key values in flashes.
- Do not inspect raw params in logs.
- Clear saved key must remove the encrypted key and redacted metadata.
- Environment key presence may be displayed, but not its value.

## Error Handling

OpenAI setup and generation failures should be clear and non-secret-bearing.

Examples:

- Missing key: `OpenAI API key is required. Add one in Settings or set OPENAI_API_KEY.`
- Failed test: show provider response summary, not request headers or key material.
- Env override: if an env key is present, explain that it takes precedence over the saved key.

## Testing

Controller and system-level tests should cover:

- Models page renders local tab by default.
- Local provider selection persists.
- Local model selection still persists through existing `ImageToText` behavior.
- Cloud settings save base URL and fixed model.
- Cloud settings save and redact API key.
- Clear saved key removes key metadata.
- Env key precedence over saved key.
- OpenAI provider uses saved UI key when env key is absent.
- OpenAI provider uses env key when env key is present.
- Missing OpenAI key returns setup-required failure.
- Test connection success and failure paths.

Existing provider tests should be updated so runtime configuration comes through the settings resolver rather than direct environment access alone.

## Out Of Scope

- Per-user provider settings.
- Fetching model lists dynamically from OpenAI.
- Multi-provider marketplace.
- OAuth or hosted secret vault integrations.
- Replacing the current local model card UI.
