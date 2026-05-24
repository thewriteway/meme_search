import { test, expect } from '@playwright/test';
import { ImageToTextsPage } from '../pages/settings/image-to-texts.page';
import { resetTestDatabase } from '../utils/db-setup';

test.describe('Image-to-Texts Settings', () => {
  let imageToTextsPage: ImageToTextsPage;

  test.beforeEach(async ({ page }) => {
    await resetTestDatabase();
    imageToTextsPage = new ImageToTextsPage(page);
  });

  test('visiting the index page shows available models heading', async () => {
    await imageToTextsPage.goto();

    const headingText = await imageToTextsPage.getHeading();
    expect(headingText).toContain('AI Models');
  });

  test('updating the current local model to all available models', async () => {
    const modelIds = [2, 3, 4, 5, 1]; // Start from 2 since 1 is already selected

    await imageToTextsPage.goto();

    const defaultSelected = await imageToTextsPage.isModelSelected(1);
    expect(defaultSelected).toBe(true);

    for (const modelId of modelIds) {
      await imageToTextsPage.selectModel(modelId);
      await imageToTextsPage.saveLocalSelection();

      const nowSelected = await imageToTextsPage.isModelSelected(modelId);
      expect(nowSelected).toBe(true);

      const allIds = [1, 2, 3, 4, 5];
      for (const otherId of allIds) {
        if (otherId !== modelId) {
          const otherSelected = await imageToTextsPage.isModelSelected(otherId);
          expect(otherSelected).toBe(false);
        }
      }
    }
  });

  test('only one local model can be selected at a time', async () => {
    await imageToTextsPage.goto();

    expect(await imageToTextsPage.isModelSelected(1)).toBe(true);
    expect(await imageToTextsPage.isModelSelected(2)).toBe(false);

    await imageToTextsPage.selectModel(2);
    expect(await imageToTextsPage.isModelSelected(1)).toBe(false);
    expect(await imageToTextsPage.isModelSelected(2)).toBe(true);

    await imageToTextsPage.selectModel(3);
    expect(await imageToTextsPage.isModelSelected(1)).toBe(false);
    expect(await imageToTextsPage.isModelSelected(2)).toBe(false);
    expect(await imageToTextsPage.isModelSelected(3)).toBe(true);

    await imageToTextsPage.selectModel(1);
    expect(await imageToTextsPage.isModelSelected(1)).toBe(true);
    expect(await imageToTextsPage.isModelSelected(2)).toBe(false);
    expect(await imageToTextsPage.isModelSelected(3)).toBe(false);
  });

  test('switching between local and OpenAI-compatible provider settings', async ({ page }) => {
    const fakeKey = 'sk-playwright-provider-1234';

    await imageToTextsPage.goto();
    await expect(page.getByRole('heading', { name: 'Local model' })).toBeVisible();
    await expect(page.getByText('Choose one local model. This is the default path for Meme Search.')).toBeVisible();
    await expect(imageToTextsPage.saveLocalButton).toBeVisible();

    await imageToTextsPage.openCloudTab();
    await expect(page.getByRole('heading', { name: 'OpenAI-compatible provider' })).toBeVisible();
    await expect(imageToTextsPage.apiKeyInput).toHaveValue('');
    await expect(imageToTextsPage.saveCloudButton).toBeVisible();
    await expect(page.getByRole('button', { name: 'Test connection' })).toBeVisible();
    await expect(imageToTextsPage.clearSavedKeyButton).toBeVisible();

    await expect(await imageToTextsPage.cloudModelOptions()).toEqual([
      'gpt-4o-mini',
      'gpt-4.1-mini',
      'gpt-4.1',
    ]);

    await imageToTextsPage.saveCloudSettings({
      baseUrl: 'http://openai.test/v1',
      model: 'gpt-4.1-mini',
      apiKey: fakeKey,
    });

    await expect(page.getByText('OpenAI-compatible provider settings saved.')).toBeVisible();
    await expect(page.getByText('sk-...1234')).toBeVisible();
    await expect(page.getByText(fakeKey)).toHaveCount(0);
    await expect(page.getByText('Not tested')).toBeVisible();
    await expect(imageToTextsPage.baseUrlInput).toHaveValue('http://openai.test/v1');
    await expect(imageToTextsPage.cloudModelSelect).toHaveValue('gpt-4.1-mini');
    await expect(imageToTextsPage.apiKeyInput).toHaveValue('');

    await imageToTextsPage.clearSavedKey();
    await expect(page.getByText('Saved OpenAI API key cleared.')).toBeVisible();
    await expect(page.getByText('Not saved')).toBeVisible();
    await expect(page.getByText('sk-...1234')).toHaveCount(0);

    await imageToTextsPage.openLocalTab();
    await imageToTextsPage.selectModel(2);
    await imageToTextsPage.saveLocalSelection();
    await expect(page.getByText('Current model set to:')).toBeVisible();
    expect(await imageToTextsPage.isModelSelected(2)).toBe(true);

    await imageToTextsPage.openCloudTab();
    await expect(page.getByRole('heading', { name: 'OpenAI-compatible provider' })).toBeVisible();
    await expect(page.getByText('Active')).toHaveCount(1);
  });
});
