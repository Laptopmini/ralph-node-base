const { chromium } = require("playwright");

async function analyzeStyle(url) {
  // Launch browser (headless by default)
  const browser = await chromium.launch();
  const page = await browser.newPage();
  let exitCode = 0;

  console.log(`Analyzing ${url}...`);

  try {
    // Wait until there are no network connections for at least 500 ms
    await page.goto(url, { waitUntil: "networkidle" });

    // 1. Take a screenshot of the viewport (or set fullPage: true)
    const screenshotPath = ".maestro.screenshot.png";
    await page.screenshot({ path: screenshotPath });

    // 2. Extract CSS variables and basic computed styles
    const styles = await page.evaluate(() => {
      const root = document.documentElement;
      const computedStyle = getComputedStyle(root);
      const bodyStyle = getComputedStyle(document.body);

      // Iterate through computed styles to find CSS variables (e.g., Tailwind/custom vars)
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

    console.log("\n=== STYLE ANALYSIS COMPLETE ===");
    console.log(`Screenshot saved to: ${screenshotPath}`);
    console.log("\nExtracted Styles:");
    console.log(JSON.stringify(styles, null, 2));
  } catch (error) {
    console.error(`Failed to analyze URL: ${error.message}`);
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
