import { test, expect } from "@playwright/test";

test("about:blank has empty title", async ({ page }) => {
  await page.goto("about:blank");
  const title = await page.title();
  expect(title).toBe("");
});
