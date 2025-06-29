# Deprecated Files

These files have been replaced by the new direct profile selection system implemented in the toolkit refactoring.

## Replaced Files:
- `vpn_env.sh` → Use `--profile` and `--environment` parameters in individual scripts
- `env_manager.sh` → Use `lib/profile_selector.sh`
- `.current_env` → No longer needed (stateless operation)

## Migration Guide:

### Before (stateful):
```bash
./admin-tools/vpn_env.sh switch production
./admin-tools/aws_vpn_admin.sh
```

### After (explicit):
```bash
./admin-tools/aws_vpn_admin.sh --profile production
# OR interactive selection:
./admin-tools/aws_vpn_admin.sh
```

## Benefits of New System:
- ✅ **No hidden state** - explicit profile selection every time
- ✅ **Safety** - no accidental wrong-environment operations
- ✅ **Simplicity** - each script is self-contained
- ✅ **Consistency** - all scripts follow the same pattern

## Rollback Information:
If you need to rollback to the old system, you can restore these files from this directory. However, the new system is recommended for better safety and usability.

**Removal Timeline:** These files will be permanently removed after 2 weeks of testing the new system (after 2025-07-13).