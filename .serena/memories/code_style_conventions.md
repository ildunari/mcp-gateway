# Code Style and Conventions

## JavaScript/Node.js Standards

### Module System
- Use ES6 modules (import/export) instead of CommonJS
- Add `"type": "module"` to package.json for ES6 module support

### Code Style
- **Indentation**: 2 spaces
- **Quotes**: Single quotes for strings
- **Semicolons**: Use semicolons
- **Line Length**: Max 120 characters
- **Async/Await**: Prefer over promises/callbacks

### Naming Conventions
- **Files**: kebab-case (e.g., `server-registry.js`)
- **Classes**: PascalCase (e.g., `ServerRegistry`)
- **Functions/Variables**: camelCase (e.g., `getServerStatus`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_TIMEOUT`)
- **Private methods**: Prefix with underscore (e.g., `_handleError`)

### Error Handling
- Always use try-catch for async operations
- Log errors with context using Winston logger
- Return meaningful error messages to clients
- Never expose internal errors to external clients

### Security Practices
- Never commit `.env` files
- Always validate input data
- Use environment variables for sensitive config
- Implement proper authentication checks
- Rate limit all public endpoints

### Documentation
- Add JSDoc comments for functions
- Include parameter types and return values
- Document complex logic inline
- Keep README.md updated

### Testing Conventions
- Test files named `*.test.js`
- Use descriptive test names
- Test both success and error cases
- Mock external dependencies

### Project Structure
```
src/
  ├── server.js       # Main entry point
  ├── auth.js         # Authentication logic
  ├── registry.js     # Server management
  └── utils/          # Utility functions
config/
  └── servers.json    # Server configurations
logs/                 # Log files (gitignored)
tests/               # Test files
```

### MCP-Specific Conventions
- Handle session IDs properly
- Clean up child processes on exit
- Log all MCP protocol interactions
- Validate MCP requests/responses