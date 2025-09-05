# Contributing to tcl-lsp.nvim

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Development Setup

1. Clone the repository
2. Run `make install` to install dependencies
3. Run `make test` to ensure everything works

## Code Style

- Follow the existing code style
- Use `make format` to format your code
- Run `make lint` to check for issues
- Ensure all tests pass with `make test`

## Testing

- Write tests for all new features
- Maintain >90% code coverage
- Include integration tests for LSP features
- Performance tests should maintain <300ms response times

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for your changes
5. Run `make check` to verify everything works
6. Submit a pull request

## Commit Messages

Use conventional commit format:

- `feat: add new feature`
- `fix: resolve bug`
- `docs: update documentation`
- `test: add tests`
- `refactor: code improvements`

## Reporting Issues

Please use the GitHub issue templates when reporting bugs or requesting features.
