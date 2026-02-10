# Contributing

Thank you for your interest in contributing to this project.

## How to contribute

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/my-change`)
3. Make your changes
4. Run `az bicep lint --file main.bicep` and fix any errors
5. Commit your changes with a clear message
6. Open a pull request

## Code standards

- **Bicep linting**: All changes must pass `az bicep lint --file main.bicep` with zero errors. The project uses strict linter rules defined in `bicepconfig.json`.
- **API version**: All `Microsoft.ApiCenter` resources must use `2024-03-01` (GA). Do not upgrade to preview versions without discussion.
- **Naming**: Resource names use kebab-case. Parameters use camelCase.
- **Parameters**: Use `.bicepparam` files, not JSON parameter files.
- **Identity**: Always set `principalType` on role assignments (`'Group'`, `'ServicePrincipal'`, or `'User'`).
- **Governance**: All metadata schemas must remain `required: true`. Removing required enforcement breaks the governance model.

## What we're looking for

- Bug fixes and corrections
- Additional MCP server registration examples
- CI/CD workflow improvements
- Documentation improvements
- Support for additional deployment topologies (e.g., Internal VNet mode, Application Gateway)

## Reporting issues

Use [GitHub Issues](../../issues) for bug reports and feature requests. Include the Bicep CLI version (`az bicep version`) and any relevant error output.
