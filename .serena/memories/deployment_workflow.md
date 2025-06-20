# Deployment Workflow - GitHub & npm

## GitHub Repository
- **URL**: https://github.com/ildunari/mcp-gateway
- **Remote**: origin
- **Default Branch**: main

## npm Package
- **Package Name**: @ildunari/mcp-gateway
- **Registry**: https://registry.npmjs.org/
- **Scope**: @ildunari

## Authentication Status
- **GitHub**: ✅ Logged in (can push directly)
- **npm**: ✅ Logged in (can publish directly)

## Deployment Steps

### After Making Changes

1. **Commit Changes Locally**
```bash
git add .
git commit -m "Description of changes"
```

2. **Push to GitHub**
```bash
git push origin main
```

3. **Publish to npm** (for releases)
```bash
# First time setup (one-time only)
npm login  # Login with npm credentials

# For each release
npm version patch  # or minor/major
npm publish --access public
git push origin main --tags  # Push version tag
```

## Version Management

### Semantic Versioning
- **Patch** (0.1.x): Bug fixes, minor updates
- **Minor** (0.x.0): New features, backwards compatible
- **Major** (x.0.0): Breaking changes

### Version Commands
```bash
npm version patch    # 0.1.0 → 0.1.1
npm version minor    # 0.1.1 → 0.2.0
npm version major    # 0.2.0 → 1.0.0
```

## Important Reminders

### Before Publishing to npm
1. Ensure all tests pass
2. Update README.md with any new features
3. Check package.json has correct metadata
4. Verify .npmignore or files field in package.json
5. Run `npm pack --dry-run` to see what will be published

### GitHub Push Checklist
- [ ] All files committed
- [ ] No sensitive data in commits
- [ ] Tests passing
- [ ] Documentation updated

### npm Publish Checklist
- [ ] Version bumped appropriately
- [ ] CHANGELOG updated (if exists)
- [ ] No development files included
- [ ] Package works when installed

## Quick Deploy Commands

```bash
# Quick patch release
npm version patch && npm publish --access public && git push origin main --tags

# Quick minor release
npm version minor && npm publish --access public && git push origin main --tags
```

## First Time Setup

1. **npm Setup**
```bash
npm login
# Enter npm username, password, email
```

2. **GitHub Setup** (if not done)
```bash
git remote add origin https://github.com/ildunari/mcp-gateway.git
```

## Continuous Deployment Note

Always push to GitHub first for version control, then publish to npm for distribution. This ensures:
- Code is backed up
- Changes are tracked
- Community can contribute
- Package users can report issues