module.exports = {
  plugins: ["prettier-plugin-solidity"],
  bracketSpacing: true,
  printWidth: 80,
  semi: true,
  singleQuote: false,
  tabWidth: 2,
  trailingComma: "all",
  overrides: [
    {
      files: "*.sol",
      options: {
        parser: "solidity-parse",
        printWidth: 80,
        tabWidth: 4,
        useTabs: false,
        singleQuote: false,
        bracketSpacing: true,
        compiler: "0.8.20",
      },
    },
  ],
};
