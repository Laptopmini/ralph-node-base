Implemented first task: TypeScript configuration.

- Created `tsconfig.json` with target ES2022, module NodeNext, moduleResolution NodeNext, strict true, outDir dist/, include `**/*`.
- Created `src/index.ts` with `export {};`.
- package.json has `"type": "commonjs"` — with NodeNext module mode, TypeScript respects the package.json type field and treats .ts files as CJS. This should be compatible.
- The `include: ["**/*"]` will pick up node_modules — if tsc complains, may need to add `exclude: ["node_modules", "dist"]`. Watch for this on retry.
- Validation: `npx tsc --noEmit`
