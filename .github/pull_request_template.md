## Summary
Describe what this pull request changes.

## Type of change
- [ ] Bug fix
- [ ] Documentation update
- [ ] New plugin/module
- [ ] Refactor/maintenance
- [ ] CI/release change

## Testing
Commands run:

```bash
bash -n thor.sh install.sh update.sh uninstall.sh gui/thor-gui.sh modules/**/*.sh
shellcheck thor.sh install.sh update.sh uninstall.sh gui/*.sh modules/**/*.sh
shfmt -d thor.sh install.sh update.sh uninstall.sh gui/*.sh modules/**/*.sh
```

## Security checklist
- [ ] No secrets, tokens, cookies, or private target data are included.
- [ ] The change preserves authorized-use safety messaging.
- [ ] The change does not add exploitation or bypass logic.
- [ ] Reports and logs preserve real errors without inventing findings.
