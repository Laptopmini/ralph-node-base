const { chromium } = require("playwright");

async function analyzeStyle(url) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  let exitCode = 0;

  try {
    await page.goto(url, { waitUntil: "networkidle" });

    // Scroll to the bottom of the page
    await page.evaluate(async () => {
      await new Promise((resolve) => {
        let totalHeight = 0;
        const distance = 100;
        const timer = setInterval(() => {
          const scrollHeight = document.body.scrollHeight;
          window.scrollBy(0, distance);
          totalHeight += distance;

          if (totalHeight >= scrollHeight - window.innerHeight) {
            clearInterval(timer);
            resolve();
          }
        }, 100); // Scroll down every 100ms
      });
    });

    // Go back to the top of the page
    await page.evaluate(() => window.scrollTo(0, 0));

    // Wait 500ms for any sticky headers or scroll-triggered animations to reset
    await page.evaluate(() => new Promise((resolve) => setTimeout(resolve, 500)));

    // Capture full-page screenshot
    const screenshotPath = ".maestro.screenshot.png";
    await page.screenshot({ path: screenshotPath, fullPage: true });

    // Extract CSS tokens
    const styles = await page.evaluate(() => {
      const root = document.documentElement;
      const computedStyle = getComputedStyle(root);
      const bodyStyle = getComputedStyle(document.body);

      // Iterate through computed styles to find CSS variables
      const cssVars = {};
      for (let i = 0; i < computedStyle.length; i++) {
        const prop = computedStyle[i];
        if (prop.startsWith("--")) {
          cssVars[prop] = computedStyle.getPropertyValue(prop).trim();
        }
      }

      return {
        baseBackground: bodyStyle.backgroundColor,
        baseColor: bodyStyle.color,
        primaryFontFamily: bodyStyle.fontFamily,
        rootVariables: Object.keys(cssVars).length > 0 ? cssVars : "No root CSS variables found.",
      };
    });

    // Log results
    console.log(JSON.stringify(styles, null, 2));
  } catch (error) {
    console.error(`${error.message}`);
    exitCode = 1;
  } finally {
    await browser.close();
  }
  process.exit(exitCode);
}

const url = process.argv[2];
if (!url) {
  console.error("Please provide a URL. Example: node analyze_style.js https://bright.ai/");
  process.exit(1);
}

analyzeStyle(url);
