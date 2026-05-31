import { Page } from '@playwright/test';

/**
 * Page Object for Image Uploads page
 * Handles interactions with the drag-and-drop upload interface
 */
export class ImageUploadsPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/image_uploads/new');
    await this.page.waitForLoadState('networkidle');
  }

  async getHeading(): Promise<string> {
    const heading = this.page.locator('h1').first();
    return (await heading.textContent()) || '';
  }

  async isDropzoneVisible(): Promise<boolean> {
    const dropzone = this.page.locator('[data-file-upload-target="dropzone"]');
    return dropzone.isVisible();
  }

  async isUploadButtonDisabled(): Promise<boolean> {
    const uploadButton = this.page.locator('[data-file-upload-target="uploadButton"]');
    return uploadButton.isDisabled();
  }

  async uploadFile(filePath: string) {
    const fileInput = this.page.locator('input[type="file"]');
    await fileInput.setInputFiles(filePath);
  }

  async pasteImage(base64Image: string, filename = 'clipboard.png', mimeType = 'image/png') {
    await this.pasteFiles([{ base64: base64Image, filename, mimeType }]);
  }

  async pasteFiles(files: Array<{ base64: string; filename: string; mimeType: string }>) {
    await this.page.evaluate(
      ({ files }) => {
        const browserGlobal = globalThis as any;
        const dataTransfer = new browserGlobal.DataTransfer();

        for (const fileDetails of files) {
          const bytes = Uint8Array.from(browserGlobal.atob(fileDetails.base64), (character: string) => character.charCodeAt(0));
          const file = new browserGlobal.File([bytes], fileDetails.filename, { type: fileDetails.mimeType });
          dataTransfer.items.add(file);
        }

        const pasteEvent = new browserGlobal.Event('paste', { bubbles: true, cancelable: true });

        Object.defineProperty(pasteEvent, 'clipboardData', {
          value: dataTransfer,
        });

        browserGlobal.dispatchEvent(pasteEvent);
      },
      { files }
    );
  }

  async getPreviewCount(): Promise<number> {
    const preview = this.page.locator('[data-file-upload-target="preview"]');
    const items = preview.locator('> div');
    return items.count();
  }

  async getPreviewFilenames(): Promise<string[]> {
    return this.page
      .locator('[data-file-upload-target="preview"] p.text-sm')
      .evaluateAll((nodes) => nodes.map((node) => node.textContent?.trim() || ''));
  }

  async clickUpload() {
    const uploadButton = this.page.locator('[data-file-upload-target="uploadButton"]');
    await uploadButton.click();
  }

  async hasSuccessMessage(): Promise<boolean> {
    const successMessage = this.page.locator('[data-file-upload-target="successMessage"]');
    const isVisible = await successMessage.isVisible();
    if (!isVisible) return false;

    // Check if it has content
    const text = await successMessage.textContent();
    return text !== null && text.length > 0;
  }

  async hasErrorMessage(): Promise<boolean> {
    const errorMessage = this.page.locator('[data-file-upload-target="errorMessage"]');
    const isVisible = await errorMessage.isVisible();
    if (!isVisible) return false;

    // Check if it has content
    const text = await errorMessage.textContent();
    return text !== null && text.length > 0;
  }

  async removeFirstPreview() {
    const removeButton = this.page.locator('[data-action="click->file-upload#removeFile"]').first();
    await removeButton.click();
  }

  async clickBackToImages() {
    await this.page.click('text=Back to Images');
  }
}
