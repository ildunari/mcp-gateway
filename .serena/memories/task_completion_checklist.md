# Task Completion Checklist

When completing any coding task in the MCP Gateway project, ensure you:

## Before Committing Code

### 1. Code Quality
- [ ] Code follows the established style conventions
- [ ] No console.log statements left in production code
- [ ] All functions have proper error handling
- [ ] Sensitive data is in environment variables, not hardcoded

### 2. Testing
- [ ] Test the server locally: `npm test`
- [ ] Verify health endpoint: `curl http://localhost:4242/health`
- [ ] Test new MCP server endpoints if added
- [ ] Check logs for any errors: `tail -f logs/combined.log`

### 3. Security Review
- [ ] Authentication is properly implemented
- [ ] No secrets in code (check for tokens, keys)
- [ ] CORS is properly configured
- [ ] Rate limiting is in place

### 4. Documentation
- [ ] Update README.md if adding new features
- [ ] Add JSDoc comments for new functions
- [ ] Update CLAUDE.md if architecture changes
- [ ] Document any new environment variables

### 5. Dependencies
- [ ] Run `npm install` after adding new packages
- [ ] Check for vulnerabilities: `npm audit`
- [ ] Update package-lock.json is committed

### 6. Cloudflare Integration (if deploying)
- [ ] Test with Cloudflare tunnel locally first
- [ ] Verify DNS records are correct
- [ ] Check tunnel configuration matches server port

### 7. Final Checks
- [ ] All files saved
- [ ] `.gitignore` excludes sensitive files
- [ ] No debug code left in
- [ ] Server starts without errors
- [ ] Graceful shutdown works (Ctrl+C)

## Common Issues to Check

1. **Port Conflicts**: Ensure port 4242 is free
2. **Environment Variables**: All required vars in `.env`
3. **File Permissions**: Logs directory is writable
4. **Process Cleanup**: Child processes terminate properly
5. **Memory Leaks**: Sessions are cleaned up after timeout