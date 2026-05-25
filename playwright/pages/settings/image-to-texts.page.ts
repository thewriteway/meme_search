import type { Page, Locator } from '@playwright/test';

export class ImageToTextsPage {
  readonly page: Page;
  readonly heading: Locator;

  constructor(page: Page) {
    this.page = page;
    this.heading = page.locator('h1');
  }

  /**
   * Navigate to the image-to-texts settings page
   */
  async goto(): Promise<void> {
    await this.page.goto('/settings/image_to_texts?provider_tab=local');
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Get the page heading text
   */
  async getHeading(): Promise<string> {
    return (await this.heading.textContent()) || '';
  }

  /**
   * Get a model radio input by ID
   */
  getModelRadio(modelId: number): Locator {
    return this.page.locator(`#image_to_text_${modelId}`);
  }

  /**
   * Get a model label by ID
   */
  getModelLabel(modelId: number): Locator {
    return this.page.locator(`label[for='image_to_text_${modelId}']`);
  }

  /**
   * Check if a model is selected
   */
  async isModelSelected(modelId: number): Promise<boolean> {
    return await this.getModelRadio(modelId).isChecked();
  }

  /**
   * Select a model by clicking its label
   */
  async selectModel(modelId: number): Promise<void> {
    const label = this.getModelLabel(modelId);
    await label.click();
    // Wait for the state to update (toggle switches can have animations/transitions)
    await this.page.waitForTimeout(500);
  }

  /**
   * Get all model radio inputs
   */
  async getAllModelRadios(): Promise<Locator[]> {
    return await this.page.locator('input[name="current_id"]').all();
  }

  /**
   * Get the count of model radio inputs
   */
  async getModelCount(): Promise<number> {
    return await this.page.locator('input[name="current_id"]').count();
  }

  /**
   * Verify that only one model is selected
   */
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
