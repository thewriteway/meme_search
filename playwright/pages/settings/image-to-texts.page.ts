import type { Page, Locator } from '@playwright/test';

export class ImageToTextsPage {
  readonly page: Page;
  readonly heading: Locator;
  readonly localTab: Locator;
  readonly openAiTab: Locator;
  readonly saveLocalButton: Locator;
  readonly saveCloudButton: Locator;
  readonly clearSavedKeyButton: Locator;
  readonly baseUrlInput: Locator;
  readonly cloudModelSelect: Locator;
  readonly apiKeyInput: Locator;

  constructor(page: Page) {
    this.page = page;
    this.heading = page.locator('h1');
    this.localTab = page.getByRole('button', { name: 'Local generator' });
    this.openAiTab = page.getByRole('button', { name: 'OpenAI-compatible API' });
    this.saveLocalButton = page.getByRole('button', { name: 'Save Local Selection' });
    this.saveCloudButton = page.getByRole('button', { name: 'Save Cloud Selection' });
    this.clearSavedKeyButton = page.getByRole('button', { name: 'Clear saved key' });
    this.baseUrlInput = page.getByLabel('Base URL');
    this.cloudModelSelect = page.getByLabel('Cloud model');
    this.apiKeyInput = page.getByLabel('API key');
  }

  async goto(providerTab: 'local' | 'openai' = 'local'): Promise<void> {
    await this.page.goto(`/settings/image_to_texts?provider_tab=${providerTab}`);
    await this.page.waitForLoadState('networkidle');
  }

  async getHeading(): Promise<string> {
    return (await this.heading.textContent()) || '';
  }

  getModelRadio(modelId: number): Locator {
    return this.page.locator(`#image_to_text_${modelId}`);
  }

  getModelLabel(modelId: number): Locator {
    return this.page.locator(`label[for='image_to_text_${modelId}']`);
  }

  async isModelSelected(modelId: number): Promise<boolean> {
    return await this.getModelRadio(modelId).isChecked();
  }

  async selectModel(modelId: number): Promise<void> {
    await this.getModelLabel(modelId).click();
  }

  async saveLocalSelection(): Promise<void> {
    await Promise.all([
      this.page.waitForURL(/\/settings\/image_to_texts\?provider_tab=local/),
      this.saveLocalButton.click(),
    ]);
    await this.page.waitForLoadState('networkidle');
  }

  async getModelCount(): Promise<number> {
    return await this.page.locator('input[name="current_id"]').count();
  }

  async openLocalTab(): Promise<void> {
    await Promise.all([
      this.page.waitForURL(/\/settings\/image_to_texts\?provider_tab=local/),
      this.localTab.click(),
    ]);
    await this.page.waitForLoadState('networkidle');
  }

  async openCloudTab(): Promise<void> {
    await Promise.all([
      this.page.waitForURL(/\/settings\/image_to_texts\?provider_tab=openai/),
      this.openAiTab.click(),
    ]);
    await this.page.waitForLoadState('networkidle');
  }

  async saveCloudSettings(options: { baseUrl: string; model: string; apiKey?: string }): Promise<void> {
    await this.baseUrlInput.fill(options.baseUrl);
    await this.cloudModelSelect.selectOption(options.model);

    if (options.apiKey !== undefined) {
      await this.apiKeyInput.fill(options.apiKey);
    }

    await Promise.all([
      this.page.waitForURL(/\/settings\/image_to_texts\?provider_tab=openai/),
      this.saveCloudButton.click(),
    ]);
    await this.page.waitForLoadState('networkidle');
  }

  async clearSavedKey(): Promise<void> {
    await Promise.all([
      this.page.waitForURL(/\/settings\/image_to_texts\?provider_tab=openai/),
      this.clearSavedKeyButton.click(),
    ]);
    await this.page.waitForLoadState('networkidle');
  }

  async cloudModelOptions(): Promise<string[]> {
    return await this.cloudModelSelect.locator('option').evaluateAll((options) =>
      options.map((option) => (option as HTMLOptionElement).value),
    );
  }

  async verifyOnlyOneModelSelected(selectedId: number, allIds: number[]): Promise<void> {
    for (const id of allIds) {
      const isChecked = await this.isModelSelected(id);
      if (id === selectedId) {
        if (!isChecked) {
          throw new Error(`Model ${id} should be selected but is not`);
        }
      } else {
        if (isChecked) {
          throw new Error(`Model ${id} should not be selected but is`);
        }
      }
    }
  }
}
