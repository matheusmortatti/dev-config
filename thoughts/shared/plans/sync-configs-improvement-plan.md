# sync-configs.sh Enhancement Implementation Plan

## Overview

This plan implements systematic improvements to the sync-configs.sh script based on the comprehensive analysis in `thoughts/shared/research/2025-09-07_05-03-05_sync-configs-analysis.md`. The improvements are organized into phases based on dependency relationships and the priority matrix (High Impact/Low Effort first).

## Current State Analysis

The current script (`sync-configs.sh:1-132`) implements a robust bidirectional configuration synchronization system with:
- Data-driven design using `CONFIG_MAPPINGS` array
- Automatic backup functionality 
- Basic error handling with `set -e`
- Support for both files and directories
- Pull/push mode operations

## Desired End State

After completing this plan, the sync-configs.sh script will have:
- **Dry-run mode** for safe preview of operations
- **Enhanced error handling** with proper validation and recovery
- **Backup management** with automatic cleanup and retention policies
- **Improved user experience** with verbosity controls and better feedback
- **Rollback capability** for easy recovery from errors
- **Configuration validation** to prevent common mistakes
- **Cross-platform compatibility** for broader usage

### Verification Criteria:
- All existing functionality preserved and working
- New features demonstrated through manual testing
- Script passes shellcheck linting
- Comprehensive test coverage for critical paths

## What We're NOT Doing

- Encryption support (complex feature requiring key management)
- Template system with variable substitution (would require major architecture changes)
- GUI interface (out of scope for CLI tool)
- Integration with external config management systems

## Implementation Approach

**Strategy**: Incremental enhancement preserving backward compatibility
**Testing**: Each phase includes comprehensive testing before moving to next phase
**Rollback**: Keep original script as backup during development

---

## Phase 1: Enhanced Error Handling and Validation

### Overview
Establish robust foundation with better error detection, input validation, and safer operations.

**Dependencies**: None (foundational phase)

### Changes Required:

#### 1. Script Header and Safety Improvements
**File**: `sync-configs.sh`
**Lines**: `1-6`

```bash
#!/bin/bash

# Enhanced error handling - catch undefined variables and pipe failures
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config-backups"
```

#### 2. Add Configuration Validation Functions
**File**: `sync-configs.sh` 
**Location**: After line 15 (before usage function)

```bash
# Validate mapping format: name:system_path:repo_path:type
validate_mapping_format() {
    local mapping="$1"
    if [[ ! "$mapping" =~ ^[^:]+:[^:]+:[^:]+:(file|dir)$ ]]; then
        echo "ERROR: Invalid mapping format: $mapping" >&2
        echo "Expected format: name:system_path:repo_path:type" >&2
        return 1
    fi
}

# Validate paths and permissions before operations
validate_paths() {
    local system_path="$1"
    local repo_path="$2"
    local mode="$3"
    
    if [[ "$mode" == "pull" ]]; then
        if [[ ! -e "$system_path" ]]; then
            echo "WARNING: Source path does not exist: $system_path" >&2
            return 1
        fi
        if [[ ! -r "$system_path" ]]; then
            echo "ERROR: No read permission for: $system_path" >&2
            return 1
        fi
        # Check write permission for repo directory
        local repo_dir="$(dirname "$repo_path")"
        if [[ ! -w "$repo_dir" ]] && [[ ! -w "$(dirname "$repo_dir")" ]]; then
            echo "ERROR: No write permission for repository path: $repo_dir" >&2
            return 1
        fi
    elif [[ "$mode" == "push" ]]; then
        if [[ ! -e "$repo_path" ]]; then
            echo "WARNING: Repository path does not exist: $repo_path" >&2
            return 1
        fi
        if [[ ! -r "$repo_path" ]]; then
            echo "ERROR: No read permission for: $repo_path" >&2
            return 1
        fi
        # Check write permission for system directory
        local system_dir="$(dirname "$system_path")"
        if [[ ! -w "$system_dir" ]] && [[ ! -w "$(dirname "$system_dir")" ]]; then
            echo "ERROR: No write permission for system path: $system_dir" >&2
            return 1
        fi
    fi
    
    return 0
}

# Validate all mappings at startup
validate_all_mappings() {
    local errors=0
    echo "Validating configuration mappings..."
    
    for mapping in "${CONFIG_MAPPINGS[@]}"; do
        if ! validate_mapping_format "$mapping"; then
            ((errors++))
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        echo "ERROR: Found $errors invalid mapping(s). Please fix CONFIG_MAPPINGS." >&2
        exit 1
    fi
    
    echo "✓ All mappings validated successfully"
}
```

#### 3. Update sync_config Function
**File**: `sync-configs.sh`
**Lines**: `46-99`

Replace the sync_config function with enhanced error handling:

```bash
sync_config() {
    local name="$1"
    local system_path="$2"
    local repo_path="$3"
    local type="$4"
    local mode="$5"
    
    echo "Syncing $name config..."
    
    # Validate paths before proceeding
    if ! validate_paths "$system_path" "$repo_path" "$mode"; then
        echo "  ⚠ Skipping $name due to validation errors"
        return 1
    fi
    
    # Mode-specific operations with enhanced error handling
    if [[ "$mode" == "pull" ]]; then
        # Create backup if target exists
        if [[ -e "$repo_path" ]]; then
            if ! create_backup "$repo_path" "${name}_repo"; then
                echo "  ERROR: Failed to create backup for $repo_path" >&2
                return 1
            fi
        fi
        
        # Perform copy operation
        if [[ "$type" == "dir" ]]; then
            echo "  Copying directory: $system_path -> $repo_path"
            if ! rm -rf "$repo_path" 2>/dev/null; then
                echo "  ERROR: Failed to remove existing directory: $repo_path" >&2
                return 1
            fi
            if ! cp -r "$system_path" "$repo_path"; then
                echo "  ERROR: Failed to copy directory: $system_path -> $repo_path" >&2
                return 1
            fi
        else
            echo "  Copying file: $system_path -> $repo_path"
            if ! mkdir -p "$(dirname "$repo_path")"; then
                echo "  ERROR: Failed to create parent directory for: $repo_path" >&2
                return 1
            fi
            if ! cp "$system_path" "$repo_path"; then
                echo "  ERROR: Failed to copy file: $system_path -> $repo_path" >&2
                return 1
            fi
        fi
        
    elif [[ "$mode" == "push" ]]; then
        # Create backup if target exists
        if [[ -e "$system_path" ]]; then
            if ! create_backup "$system_path" "${name}_system"; then
                echo "  ERROR: Failed to create backup for $system_path" >&2
                return 1
            fi
        fi
        
        # Perform copy operation
        if [[ "$type" == "dir" ]]; then
            echo "  Copying directory: $repo_path -> $system_path"
            if ! rm -rf "$system_path" 2>/dev/null; then
                echo "  ERROR: Failed to remove existing directory: $system_path" >&2
                return 1
            fi
            if ! mkdir -p "$(dirname "$system_path")"; then
                echo "  ERROR: Failed to create parent directory for: $system_path" >&2
                return 1
            fi
            if ! cp -r "$repo_path" "$system_path"; then
                echo "  ERROR: Failed to copy directory: $repo_path -> $system_path" >&2
                return 1
            fi
        else
            echo "  Copying file: $repo_path -> $system_path"
            if ! mkdir -p "$(dirname "$system_path")"; then
                echo "  ERROR: Failed to create parent directory for: $system_path" >&2
                return 1
            fi
            if ! cp "$repo_path" "$system_path"; then
                echo "  ERROR: Failed to copy file: $repo_path -> $system_path" >&2
                return 1
            fi
        fi
    fi
    
    echo "  ✓ $name config synced successfully"
    return 0
}
```

#### 4. Update create_backup Function
**File**: `sync-configs.sh`
**Lines**: `28-44`

```bash
create_backup() {
    local target="$1"
    local backup_name="$2"
    
    if [[ -e "$target" ]]; then
        if ! mkdir -p "$BACKUP_DIR"; then
            echo "ERROR: Failed to create backup directory: $BACKUP_DIR" >&2
            return 1
        fi
        
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_path="$BACKUP_DIR/${backup_name}_${timestamp}"
        
        echo "  Creating backup: $backup_path"
        if [[ -d "$target" ]]; then
            if ! cp -r "$target" "$backup_path"; then
                echo "  ERROR: Failed to backup directory: $target" >&2
                return 1
            fi
        else
            if ! cp "$target" "$backup_path"; then
                echo "  ERROR: Failed to backup file: $target" >&2
                return 1
            fi
        fi
        echo "  ✓ Backup created successfully"
    fi
    
    return 0
}
```

#### 5. Update main Function
**File**: `sync-configs.sh`
**Lines**: `101-132`

```bash
main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi
    
    local mode="$1"
    
    if [[ "$mode" != "pull" && "$mode" != "push" ]]; then
        echo "ERROR: Invalid mode '$mode'" >&2
        usage
        exit 1
    fi
    
    echo "=== Config Sync Tool ==="
    echo "Mode: $mode"
    echo "Repository: $SCRIPT_DIR"
    echo ""
    
    # Validate all mappings before starting
    validate_all_mappings
    echo ""
    
    local success_count=0
    local total_count=${#CONFIG_MAPPINGS[@]}
    
    for mapping in "${CONFIG_MAPPINGS[@]}"; do
        IFS=':' read -r name system_path repo_path type <<< "$mapping"
        if sync_config "$name" "$system_path" "$repo_path" "$type" "$mode"; then
            ((success_count++))
        fi
        echo ""
    done
    
    echo "=== Sync Summary ==="
    echo "Successful: $success_count/$total_count configurations"
    
    if [[ $success_count -eq $total_count ]]; then
        echo "✓ All configurations synced successfully!"
    else
        echo "⚠ Some configurations failed to sync. Check output above."
        exit 1
    fi
    
    if [[ -d "$BACKUP_DIR" ]]; then
        echo "Backups created in: $BACKUP_DIR"
    fi
}
```

### Success Criteria:

#### Automated Verification:
- [x] Script passes shellcheck: `shellcheck sync-configs.sh`
- [x] No syntax errors: `bash -n sync-configs.sh`
- [x] Invalid mapping format detected: Test with malformed CONFIG_MAPPINGS
- [x] Permission errors handled gracefully: Test with read-only directories

#### Manual Verification:
- [x] Error messages are clear and actionable
- [x] Script handles missing source files gracefully
- [x] Permission errors don't cause script crashes
- [x] Backup failures are properly reported
- [x] Success/failure summary is accurate

---

## Phase 2: Dry-Run Mode

### Overview
Add safe preview functionality to show what operations would be performed without actually executing them.

**Dependencies**: Phase 1 (requires enhanced error handling and validation)

### Changes Required:

#### 1. Add Dry-Run Global Variable and Argument Parsing
**File**: `sync-configs.sh`
**Lines**: After line 7 (after BACKUP_DIR)

```bash
# Global dry-run flag
DRY_RUN=false
```

#### 2. Update usage Function
**File**: `sync-configs.sh`
**Lines**: `16-26`

```bash
usage() {
    echo "Usage: $0 [--dry-run] {pull|push}"
    echo ""
    echo "  pull      - Copy configs from system to repository"
    echo "  push      - Copy configs from repository to system"
    echo "  --dry-run - Preview operations without making changes"
    echo ""
    echo "Configurations managed:"
    echo "  - Claude config (claude.md, agents/, commands/ from ~/.claude/)"
    echo "  - Tmux config (~/.tmux.conf)"
    echo "  - Ghostty config (~/Library/Application Support/com.mitchellh.ghostty/config)"
    echo ""
    echo "Examples:"
    echo "  $0 pull              # Sync from system to repo"
    echo "  $0 --dry-run push    # Preview push operations"
}
```

#### 3. Add Dry-Run Helper Functions
**File**: `sync-configs.sh`
**Location**: After validate_all_mappings function

```bash
# Execute command or show what would be executed
dry_run_execute() {
    local operation="$1"
    shift
    local cmd="$*"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] $operation: $cmd"
        return 0
    else
        echo "  $operation: $cmd"
        eval "$cmd"
        return $?
    fi
}

# Show file operation details in dry-run mode
show_dry_run_details() {
    local operation="$1"
    local source="$2"
    local target="$3"
    local type="$4"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        return 0
    fi
    
    echo "  [DRY-RUN] $operation Details:"
    echo "    Source: $source"
    echo "    Target: $target"
    echo "    Type: $type"
    
    if [[ -e "$source" ]]; then
        if [[ "$type" == "dir" ]]; then
            local file_count=$(find "$source" -type f | wc -l)
            echo "    Files to copy: $file_count"
        else
            local size=$(stat -f%z "$source" 2>/dev/null || echo "unknown")
            echo "    File size: $size bytes"
        fi
    fi
    
    if [[ -e "$target" ]]; then
        echo "    Target exists: Will create backup first"
    else
        echo "    Target exists: No (new file/directory)"
    fi
}
```

#### 4. Update create_backup Function for Dry-Run
**File**: `sync-configs.sh`
**Replace existing create_backup function**

```bash
create_backup() {
    local target="$1"
    local backup_name="$2"
    
    if [[ -e "$target" ]]; then
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_path="$BACKUP_DIR/${backup_name}_${timestamp}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY-RUN] Would create backup: $backup_path"
            return 0
        fi
        
        if ! mkdir -p "$BACKUP_DIR"; then
            echo "ERROR: Failed to create backup directory: $BACKUP_DIR" >&2
            return 1
        fi
        
        echo "  Creating backup: $backup_path"
        if [[ -d "$target" ]]; then
            if ! cp -r "$target" "$backup_path"; then
                echo "  ERROR: Failed to backup directory: $target" >&2
                return 1
            fi
        else
            if ! cp "$target" "$backup_path"; then
                echo "  ERROR: Failed to backup file: $target" >&2
                return 1
            fi
        fi
        echo "  ✓ Backup created successfully"
    fi
    
    return 0
}
```

#### 5. Update sync_config Function for Dry-Run
**File**: `sync-configs.sh`
**Replace the copy operations in sync_config function**

```bash
sync_config() {
    local name="$1"
    local system_path="$2"
    local repo_path="$3"
    local type="$4"
    local mode="$5"
    
    echo "Syncing $name config..."
    
    # Validate paths before proceeding
    if ! validate_paths "$system_path" "$repo_path" "$mode"; then
        echo "  ⚠ Skipping $name due to validation errors"
        return 1
    fi
    
    if [[ "$mode" == "pull" ]]; then
        show_dry_run_details "PULL" "$system_path" "$repo_path" "$type"
        
        # Create backup if target exists
        if [[ -e "$repo_path" ]]; then
            if ! create_backup "$repo_path" "${name}_repo"; then
                echo "  ERROR: Failed to create backup for $repo_path" >&2
                return 1
            fi
        fi
        
        # Perform copy operation
        if [[ "$type" == "dir" ]]; then
            echo "  Copying directory: $system_path -> $repo_path"
            if ! dry_run_execute "Remove existing directory" "rm -rf \"$repo_path\""; then
                echo "  ERROR: Failed to remove existing directory: $repo_path" >&2
                return 1
            fi
            if ! dry_run_execute "Copy directory" "cp -r \"$system_path\" \"$repo_path\""; then
                echo "  ERROR: Failed to copy directory: $system_path -> $repo_path" >&2
                return 1
            fi
        else
            echo "  Copying file: $system_path -> $repo_path"
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$(dirname \"$repo_path\")\""; then
                echo "  ERROR: Failed to create parent directory for: $repo_path" >&2
                return 1
            fi
            if ! dry_run_execute "Copy file" "cp \"$system_path\" \"$repo_path\""; then
                echo "  ERROR: Failed to copy file: $system_path -> $repo_path" >&2
                return 1
            fi
        fi
        
    elif [[ "$mode" == "push" ]]; then
        show_dry_run_details "PUSH" "$repo_path" "$system_path" "$type"
        
        # Create backup if target exists
        if [[ -e "$system_path" ]]; then
            if ! create_backup "$system_path" "${name}_system"; then
                echo "  ERROR: Failed to create backup for $system_path" >&2
                return 1
            fi
        fi
        
        # Perform copy operation
        if [[ "$type" == "dir" ]]; then
            echo "  Copying directory: $repo_path -> $system_path"
            if ! dry_run_execute "Remove existing directory" "rm -rf \"$system_path\""; then
                echo "  ERROR: Failed to remove existing directory: $system_path" >&2
                return 1
            fi
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$(dirname \"$system_path\")\""; then
                echo "  ERROR: Failed to create parent directory for: $system_path" >&2
                return 1
            fi
            if ! dry_run_execute "Copy directory" "cp -r \"$repo_path\" \"$system_path\""; then
                echo "  ERROR: Failed to copy directory: $repo_path -> $system_path" >&2
                return 1
            fi
        else
            echo "  Copying file: $repo_path -> $system_path"
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$(dirname \"$system_path\")\""; then
                echo "  ERROR: Failed to create parent directory for: $system_path" >&2
                return 1
            fi
            if ! dry_run_execute "Copy file" "cp \"$repo_path\" \"$system_path\""; then
                echo "  ERROR: Failed to copy file: $repo_path -> $system_path" >&2
                return 1
            fi
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would complete: $name config sync"
    else
        echo "  ✓ $name config synced successfully"
    fi
    return 0
}
```

#### 6. Update main Function for Argument Parsing
**File**: `sync-configs.sh`
**Replace existing main function**

```bash
main() {
    # Parse arguments for dry-run flag
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            pull|push)
                local mode="$1"
                shift
                ;;
            *)
                echo "ERROR: Unknown argument '$1'" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required mode argument
    if [[ -z "${mode:-}" ]]; then
        echo "ERROR: Mode (pull|push) is required" >&2
        usage
        exit 1
    fi
    
    # Display mode information
    echo "=== Config Sync Tool ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: $mode (DRY-RUN - no changes will be made)"
    else
        echo "Mode: $mode"
    fi
    echo "Repository: $SCRIPT_DIR"
    echo ""
    
    # Validate all mappings before starting
    validate_all_mappings
    echo ""
    
    local success_count=0
    local total_count=${#CONFIG_MAPPINGS[@]}
    
    for mapping in "${CONFIG_MAPPINGS[@]}"; do
        IFS=':' read -r name system_path repo_path type <<< "$mapping"
        if sync_config "$name" "$system_path" "$repo_path" "$type" "$mode"; then
            ((success_count++))
        fi
        echo ""
    done
    
    echo "=== Sync Summary ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN completed: $success_count/$total_count configurations would be synced"
        echo "✓ No actual changes were made. Use without --dry-run to execute."
    else
        echo "Successful: $success_count/$total_count configurations"
        
        if [[ $success_count -eq $total_count ]]; then
            echo "✓ All configurations synced successfully!"
        else
            echo "⚠ Some configurations failed to sync. Check output above."
            exit 1
        fi
        
        if [[ -d "$BACKUP_DIR" ]]; then
            echo "Backups created in: $BACKUP_DIR"
        fi
    fi
}
```

### Success Criteria:

#### Automated Verification:
- [x] Dry-run mode doesn't create or modify files: `ls -la` before/after
- [x] Script shows correct operations in dry-run: `./sync-configs.sh --dry-run pull`
- [x] Argument parsing works correctly: Test `--dry-run pull`, `pull --dry-run`, invalid combinations
- [x] Help text updated and accurate: `./sync-configs.sh` shows new usage

#### Manual Verification:
- [x] Dry-run shows detailed operation information
- [x] File size and count information displayed for directories
- [x] Backup operations are previewed correctly
- [x] No actual file system changes occur in dry-run mode
- [x] Regular mode still works as before

---

## Phase 3: Backup Management and Retention

### Overview
Add automatic cleanup of old backups with configurable retention policy to prevent disk space issues.

**Dependencies**: Phase 2 (requires dry-run for safe testing of cleanup operations)

### Changes Required:

#### 1. Add Backup Configuration Variables
**File**: `sync-configs.sh`
**Lines**: After line 8 (after DRY_RUN)

```bash
# Backup configuration
BACKUP_RETENTION_DAYS=30
BACKUP_MAX_COUNT=100
```

#### 2. Add Backup Management Functions
**File**: `sync-configs.sh`
**Location**: After dry_run helper functions

```bash
# List all backup files sorted by modification time
list_backup_files() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        return 0
    fi
    
    find "$BACKUP_DIR" -type f -name "*_[0-9]*_[0-9]*" -exec stat -f "%m %N" {} \; 2>/dev/null | \
        sort -n | \
        cut -d' ' -f2-
}

# Clean up old backups based on retention policy
cleanup_old_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backup directory found, skipping cleanup"
        return 0
    fi
    
    echo "Checking for old backups to clean up..."
    
    # Find backups older than retention period
    local old_backups=()
    while IFS= read -r -d '' backup_file; do
        old_backups+=("$backup_file")
    done < <(find "$BACKUP_DIR" -type f -name "*_[0-9]*_[0-9]*" -mtime +$BACKUP_RETENTION_DAYS -print0 2>/dev/null)
    
    # Find excess backups beyond max count
    local all_backups=()
    while IFS= read -r backup_file; do
        if [[ -n "$backup_file" ]]; then
            all_backups+=("$backup_file")
        fi
    done < <(list_backup_files)
    
    local excess_backups=()
    if [[ ${#all_backups[@]} -gt $BACKUP_MAX_COUNT ]]; then
        local excess_count=$((${#all_backups[@]} - BACKUP_MAX_COUNT))
        for ((i=0; i<excess_count; i++)); do
            excess_backups+=("${all_backups[i]}")
        done
    fi
    
    # Combine and deduplicate cleanup candidates
    local cleanup_candidates=()
    for backup in "${old_backups[@]}" "${excess_backups[@]}"; do
        # Add to cleanup list if not already present
        local found=false
        for existing in "${cleanup_candidates[@]}"; do
            if [[ "$existing" == "$backup" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == "false" ]]; then
            cleanup_candidates+=("$backup")
        fi
    done
    
    if [[ ${#cleanup_candidates[@]} -eq 0 ]]; then
        echo "  ✓ No old backups to clean up"
        return 0
    fi
    
    echo "  Found ${#cleanup_candidates[@]} backup(s) to clean up"
    for backup_file in "${cleanup_candidates[@]}"; do
        local backup_name=$(basename "$backup_file")
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY-RUN] Would remove old backup: $backup_name"
        else
            echo "  Removing old backup: $backup_name"
            if ! rm "$backup_file"; then
                echo "  WARNING: Failed to remove backup: $backup_file" >&2
            fi
        fi
    done
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "  ✓ Backup cleanup completed"
    fi
}

# Show backup statistics
show_backup_stats() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backups found"
        return 0
    fi
    
    local backup_files=()
    while IFS= read -r backup_file; do
        if [[ -n "$backup_file" ]]; then
            backup_files+=("$backup_file")
        fi
    done < <(list_backup_files)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo "No backups found"
        return 0
    fi
    
    local total_size=0
    for backup_file in "${backup_files[@]}"; do
        if [[ -f "$backup_file" ]]; then
            local size=$(stat -f%z "$backup_file" 2>/dev/null || echo "0")
            total_size=$((total_size + size))
        elif [[ -d "$backup_file" ]]; then
            local size=$(du -sk "$backup_file" 2>/dev/null | cut -f1 || echo "0")
            total_size=$((total_size + size * 1024))
        fi
    done
    
    local total_mb=$((total_size / 1024 / 1024))
    echo "Backup Statistics:"
    echo "  Total backups: ${#backup_files[@]}"
    echo "  Total size: ${total_mb}MB"
    echo "  Retention: $BACKUP_RETENTION_DAYS days (max $BACKUP_MAX_COUNT files)"
    echo "  Location: $BACKUP_DIR"
}

# Verify backup integrity (basic check)
verify_backup_integrity() {
    local backup_path="$1"
    local original_path="$2"
    
    if [[ ! -e "$backup_path" ]]; then
        echo "  WARNING: Backup not found: $backup_path" >&2
        return 1
    fi
    
    # Basic integrity check - compare file types
    if [[ -f "$original_path" ]] && [[ ! -f "$backup_path" ]]; then
        echo "  WARNING: Type mismatch - original is file, backup is not: $backup_path" >&2
        return 1
    fi
    
    if [[ -d "$original_path" ]] && [[ ! -d "$backup_path" ]]; then
        echo "  WARNING: Type mismatch - original is directory, backup is not: $backup_path" >&2
        return 1
    fi
    
    return 0
}
```

#### 3. Update create_backup Function with Integrity Check
**File**: `sync-configs.sh`
**Replace existing create_backup function**

```bash
create_backup() {
    local target="$1"
    local backup_name="$2"
    
    if [[ -e "$target" ]]; then
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_path="$BACKUP_DIR/${backup_name}_${timestamp}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY-RUN] Would create backup: $backup_path"
            return 0
        fi
        
        if ! mkdir -p "$BACKUP_DIR"; then
            echo "ERROR: Failed to create backup directory: $BACKUP_DIR" >&2
            return 1
        fi
        
        echo "  Creating backup: $backup_path"
        if [[ -d "$target" ]]; then
            if ! cp -r "$target" "$backup_path"; then
                echo "  ERROR: Failed to backup directory: $target" >&2
                return 1
            fi
        else
            if ! cp "$target" "$backup_path"; then
                echo "  ERROR: Failed to backup file: $target" >&2
                return 1
            fi
        fi
        
        # Verify backup integrity
        if ! verify_backup_integrity "$backup_path" "$target"; then
            echo "  WARNING: Backup integrity check failed for: $backup_path" >&2
            # Don't fail the operation, just warn
        else
            echo "  ✓ Backup created and verified successfully"
        fi
    fi
    
    return 0
}
```

#### 4. Add Backup Management Command
**File**: `sync-configs.sh`
**Update usage function**

```bash
usage() {
    echo "Usage: $0 [--dry-run] {pull|push|backup-stats|backup-cleanup}"
    echo ""
    echo "  pull           - Copy configs from system to repository"
    echo "  push           - Copy configs from repository to system"
    echo "  backup-stats   - Show backup statistics and disk usage"
    echo "  backup-cleanup - Clean up old backups based on retention policy"
    echo "  --dry-run      - Preview operations without making changes"
    echo ""
    echo "Configurations managed:"
    echo "  - Claude config (claude.md, agents/, commands/ from ~/.claude/)"
    echo "  - Tmux config (~/.tmux.conf)"
    echo "  - Ghostty config (~/Library/Application Support/com.mitchellh.ghostty/config)"
    echo ""
    echo "Examples:"
    echo "  $0 pull                    # Sync from system to repo"
    echo "  $0 --dry-run push          # Preview push operations"
    echo "  $0 backup-stats            # Show backup information"
    echo "  $0 --dry-run backup-cleanup # Preview backup cleanup"
    echo ""
    echo "Backup Configuration:"
    echo "  Retention: $BACKUP_RETENTION_DAYS days"
    echo "  Max count: $BACKUP_MAX_COUNT files"
    echo "  Location: $BACKUP_DIR"
}
```

#### 5. Update main Function for Backup Commands
**File**: `sync-configs.sh`
**Replace main function argument parsing section**

```bash
main() {
    local mode=""
    
    # Parse arguments for dry-run flag and mode
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            pull|push)
                mode="$1"
                shift
                ;;
            backup-stats)
                mode="backup-stats"
                shift
                ;;
            backup-cleanup)
                mode="backup-cleanup"
                shift
                ;;
            *)
                echo "ERROR: Unknown argument '$1'" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required mode argument
    if [[ -z "$mode" ]]; then
        echo "ERROR: Mode is required" >&2
        usage
        exit 1
    fi
    
    # Handle backup management commands
    if [[ "$mode" == "backup-stats" ]]; then
        echo "=== Backup Statistics ==="
        show_backup_stats
        return 0
    elif [[ "$mode" == "backup-cleanup" ]]; then
        echo "=== Backup Cleanup ==="
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "DRY-RUN mode - no backups will actually be removed"
        fi
        cleanup_old_backups
        return 0
    fi
    
    # Display mode information for sync operations
    echo "=== Config Sync Tool ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: $mode (DRY-RUN - no changes will be made)"
    else
        echo "Mode: $mode"
    fi
    echo "Repository: $SCRIPT_DIR"
    echo ""
    
    # Validate all mappings before starting sync
    validate_all_mappings
    echo ""
    
    local success_count=0
    local total_count=${#CONFIG_MAPPINGS[@]}
    
    for mapping in "${CONFIG_MAPPINGS[@]}"; do
        IFS=':' read -r name system_path repo_path type <<< "$mapping"
        if sync_config "$name" "$system_path" "$repo_path" "$type" "$mode"; then
            ((success_count++))
        fi
        echo ""
    done
    
    # Run automatic backup cleanup after successful sync operations
    if [[ $success_count -gt 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo "=== Automatic Backup Cleanup ==="
        cleanup_old_backups
        echo ""
    fi
    
    echo "=== Sync Summary ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN completed: $success_count/$total_count configurations would be synced"
        echo "✓ No actual changes were made. Use without --dry-run to execute."
    else
        echo "Successful: $success_count/$total_count configurations"
        
        if [[ $success_count -eq $total_count ]]; then
            echo "✓ All configurations synced successfully!"
        else
            echo "⚠ Some configurations failed to sync. Check output above."
            exit 1
        fi
        
        if [[ -d "$BACKUP_DIR" ]]; then
            show_backup_stats
        fi
    fi
}
```

### Success Criteria:

#### Automated Verification:
- [x] Backup cleanup removes old files: Create test backups, run cleanup, verify removal
- [x] Backup retention policy respected: Test with various dates
- [x] Max count limit enforced: Create excess backups, verify cleanup
- [x] Dry-run doesn't actually remove files: Test cleanup dry-run

#### Manual Verification:
- [x] `backup-stats` command shows accurate information
- [x] Old backups are correctly identified and removed
- [x] Backup integrity warnings appear for corrupted backups
- [x] Automatic cleanup runs after successful sync operations
- [x] Manual cleanup commands work independently

---

## Phase 4: Verbosity Controls and Improved Output

### Overview
Add logging controls, improved user feedback, and structured output options for better user experience.

**Dependencies**: Phase 3 (requires backup management for complete feature testing)

### Changes Required:

#### 1. Add Verbosity Configuration
**File**: `sync-configs.sh`
**Lines**: After BACKUP_MAX_COUNT

```bash
# Verbosity and output configuration
VERBOSE=false
QUIET=false
SHOW_TIMESTAMPS=true
```

#### 2. Add Logging Functions
**File**: `sync-configs.sh`
**Location**: After backup management functions

```bash
# Logging functions with timestamp and level support
log_info() {
    if [[ "$QUIET" != "true" ]]; then
        if [[ "$SHOW_TIMESTAMPS" == "true" ]]; then
            echo "$(date '+%H:%M:%S') [INFO] $*"
        else
            echo "$*"
        fi
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]] && [[ "$QUIET" != "true" ]]; then
        if [[ "$SHOW_TIMESTAMPS" == "true" ]]; then
            echo "$(date '+%H:%M:%S') [VERBOSE] $*" >&2
        else
            echo "[VERBOSE] $*" >&2
        fi
    fi
}

log_warning() {
    if [[ "$QUIET" != "true" ]]; then
        if [[ "$SHOW_TIMESTAMPS" == "true" ]]; then
            echo "$(date '+%H:%M:%S') [WARNING] $*" >&2
        else
            echo "WARNING: $*" >&2
        fi
    fi
}

log_error() {
    if [[ "$SHOW_TIMESTAMPS" == "true" ]]; then
        echo "$(date '+%H:%M:%S') [ERROR] $*" >&2
    else
        echo "ERROR: $*" >&2
    fi
}

log_success() {
    if [[ "$QUIET" != "true" ]]; then
        if [[ "$SHOW_TIMESTAMPS" == "true" ]]; then
            echo "$(date '+%H:%M:%S') [SUCCESS] ✓ $*"
        else
            echo "✓ $*"
        fi
    fi
}

# Progress indicator for long operations
show_progress() {
    local current="$1"
    local total="$2"
    local operation="$3"
    
    if [[ "$QUIET" != "true" ]]; then
        local percentage=$((current * 100 / total))
        printf "\r[%d/%d] (%d%%) %s" "$current" "$total" "$percentage" "$operation"
        if [[ $current -eq $total ]]; then
            echo ""  # New line after completion
        fi
    fi
}
```

#### 3. Update Argument Parsing for Verbosity
**File**: `sync-configs.sh`
**Update usage function**

```bash
usage() {
    echo "Usage: $0 [options] {pull|push|backup-stats|backup-cleanup}"
    echo ""
    echo "Operations:"
    echo "  pull           - Copy configs from system to repository"
    echo "  push           - Copy configs from repository to system"
    echo "  backup-stats   - Show backup statistics and disk usage"
    echo "  backup-cleanup - Clean up old backups based on retention policy"
    echo ""
    echo "Options:"
    echo "  --dry-run      - Preview operations without making changes"
    echo "  -v, --verbose  - Show detailed operation information"
    echo "  -q, --quiet    - Minimize output (errors only)"
    echo "  --no-timestamp - Disable timestamps in log output"
    echo "  -h, --help     - Show this help message"
    echo ""
    echo "Configurations managed:"
    echo "  - Claude config (claude.md, agents/, commands/ from ~/.claude/)"
    echo "  - Tmux config (~/.tmux.conf)"
    echo "  - Ghostty config (~/Library/Application Support/com.mitchellh.ghostty/config)"
    echo ""
    echo "Examples:"
    echo "  $0 pull                     # Sync from system to repo"
    echo "  $0 --dry-run --verbose push # Preview push with details"
    echo "  $0 -q backup-cleanup        # Clean backups quietly"
    echo "  $0 --no-timestamp pull      # Sync without timestamps"
    echo ""
    echo "Backup Configuration:"
    echo "  Retention: $BACKUP_RETENTION_DAYS days"
    echo "  Max count: $BACKUP_MAX_COUNT files"
    echo "  Location: $BACKUP_DIR"
}
```

#### 4. Update validate_paths Function with Logging
**File**: `sync-configs.sh**
**Replace existing validate_paths function**

```bash
validate_paths() {
    local system_path="$1"
    local repo_path="$2"
    local mode="$3"
    
    log_verbose "Validating paths for $mode mode"
    log_verbose "  System path: $system_path"
    log_verbose "  Repo path: $repo_path"
    
    if [[ "$mode" == "pull" ]]; then
        if [[ ! -e "$system_path" ]]; then
            log_warning "Source path does not exist: $system_path"
            return 1
        fi
        if [[ ! -r "$system_path" ]]; then
            log_error "No read permission for: $system_path"
            return 1
        fi
        # Check write permission for repo directory
        local repo_dir="$(dirname "$repo_path")"
        if [[ ! -w "$repo_dir" ]] && [[ ! -w "$(dirname "$repo_dir")" ]]; then
            log_error "No write permission for repository path: $repo_dir"
            return 1
        fi
        log_verbose "  ✓ Pull validation passed"
    elif [[ "$mode" == "push" ]]; then
        if [[ ! -e "$repo_path" ]]; then
            log_warning "Repository path does not exist: $repo_path"
            return 1
        fi
        if [[ ! -r "$repo_path" ]]; then
            log_error "No read permission for: $repo_path"
            return 1
        fi
        # Check write permission for system directory
        local system_dir="$(dirname "$system_path")"
        if [[ ! -w "$system_dir" ]] && [[ ! -w "$(dirname "$system_dir")" ]]; then
            log_error "No write permission for system path: $system_dir"
            return 1
        fi
        log_verbose "  ✓ Push validation passed"
    fi
    
    return 0
}
```

#### 5. Update sync_config Function with Improved Logging
**File**: `sync-configs.sh`
**Replace echo statements in sync_config function**

```bash
sync_config() {
    local name="$1"
    local system_path="$2"
    local repo_path="$3"
    local type="$4"
    local mode="$5"
    
    log_info "Syncing $name config..."
    log_verbose "  Mode: $mode, Type: $type"
    
    # Validate paths before proceeding
    if ! validate_paths "$system_path" "$repo_path" "$mode"; then
        log_warning "Skipping $name due to validation errors"
        return 1
    fi
    
    if [[ "$mode" == "pull" ]]; then
        show_dry_run_details "PULL" "$system_path" "$repo_path" "$type"
        
        # Create backup if target exists
        if [[ -e "$repo_path" ]]; then
            log_verbose "Target exists, creating backup first"
            if ! create_backup "$repo_path" "${name}_repo"; then
                log_error "Failed to create backup for $repo_path"
                return 1
            fi
        fi
        
        # Perform copy operation
        if [[ "$type" == "dir" ]]; then
            log_verbose "Copying directory: $system_path -> $repo_path"
            if ! dry_run_execute "Remove existing directory" "rm -rf \"$repo_path\""; then
                log_error "Failed to remove existing directory: $repo_path"
                return 1
            fi
            if ! dry_run_execute "Copy directory" "cp -r \"$system_path\" \"$repo_path\""; then
                log_error "Failed to copy directory: $system_path -> $repo_path"
                return 1
            fi
        else
            log_verbose "Copying file: $system_path -> $repo_path"
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$(dirname \"$repo_path\")\""; then
                log_error "Failed to create parent directory for: $repo_path"
                return 1
            fi
            if ! dry_run_execute "Copy file" "cp \"$system_path\" \"$repo_path\""; then
                log_error "Failed to copy file: $system_path -> $repo_path"
                return 1
            fi
        fi
        
    elif [[ "$mode" == "push" ]]; then
        show_dry_run_details "PUSH" "$repo_path" "$system_path" "$type"
        
        # Create backup if target exists
        if [[ -e "$system_path" ]]; then
            log_verbose "Target exists, creating backup first"
            if ! create_backup "$system_path" "${name}_system"; then
                log_error "Failed to create backup for $system_path"
                return 1
            fi
        fi
        
        # Perform copy operation
        if [[ "$type" == "dir" ]]; then
            log_verbose "Copying directory: $repo_path -> $system_path"
            if ! dry_run_execute "Remove existing directory" "rm -rf \"$system_path\""; then
                log_error "Failed to remove existing directory: $system_path"
                return 1
            fi
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$(dirname \"$system_path\")\""; then
                log_error "Failed to create parent directory for: $system_path"
                return 1
            fi
            if ! dry_run_execute "Copy directory" "cp -r \"$repo_path\" \"$system_path\""; then
                log_error "Failed to copy directory: $repo_path -> $system_path"
                return 1
            fi
        else
            log_verbose "Copying file: $repo_path -> $system_path"
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$(dirname \"$system_path\")\""; then
                log_error "Failed to create parent directory for: $system_path"
                return 1
            fi
            if ! dry_run_execute "Copy file" "cp \"$repo_path\" \"$system_path\""; then
                log_error "Failed to copy file: $repo_path -> $system_path"
                return 1
            fi
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would complete: $name config sync"
    else
        log_success "$name config synced successfully"
    fi
    return 0
}
```

#### 6. Update main Function Argument Parsing
**File**: `sync-configs.sh`
**Replace argument parsing section in main function**

```bash
main() {
    local mode=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --no-timestamp)
                SHOW_TIMESTAMPS=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            pull|push|backup-stats|backup-cleanup)
                mode="$1"
                shift
                ;;
            *)
                log_error "Unknown argument '$1'"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate conflicting options
    if [[ "$VERBOSE" == "true" ]] && [[ "$QUIET" == "true" ]]; then
        log_error "Cannot use --verbose and --quiet together"
        exit 1
    fi
    
    # Validate required mode argument
    if [[ -z "$mode" ]]; then
        log_error "Mode is required"
        usage
        exit 1
    fi
    
    # Handle backup management commands
    if [[ "$mode" == "backup-stats" ]]; then
        log_info "=== Backup Statistics ==="
        show_backup_stats
        return 0
    elif [[ "$mode" == "backup-cleanup" ]]; then
        log_info "=== Backup Cleanup ==="
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY-RUN mode - no backups will actually be removed"
        fi
        cleanup_old_backups
        return 0
    fi
    
    # Display mode information for sync operations
    log_info "=== Config Sync Tool ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Mode: $mode (DRY-RUN - no changes will be made)"
    else
        log_info "Mode: $mode"
    fi
    log_info "Repository: $SCRIPT_DIR"
    if [[ "$VERBOSE" == "true" ]]; then
        log_verbose "Backup directory: $BACKUP_DIR"
        log_verbose "Retention policy: $BACKUP_RETENTION_DAYS days, max $BACKUP_MAX_COUNT files"
    fi
    
    # Validate all mappings before starting sync
    validate_all_mappings
    
    local success_count=0
    local total_count=${#CONFIG_MAPPINGS[@]}
    
    for i in "${!CONFIG_MAPPINGS[@]}"; do
        local mapping="${CONFIG_MAPPINGS[i]}"
        show_progress $((i + 1)) $total_count "Processing configurations..."
        
        IFS=':' read -r name system_path repo_path type <<< "$mapping"
        if sync_config "$name" "$system_path" "$repo_path" "$type" "$mode"; then
            ((success_count++))
        fi
        
        if [[ "$QUIET" != "true" ]]; then
            echo ""  # Add spacing between configs
        fi
    done
    
    # Run automatic backup cleanup after successful sync operations
    if [[ $success_count -gt 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_info "=== Automatic Backup Cleanup ==="
        cleanup_old_backups
    fi
    
    # Final summary
    log_info "=== Sync Summary ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN completed: $success_count/$total_count configurations would be synced"
        log_success "No actual changes were made. Use without --dry-run to execute."
    else
        log_info "Successful: $success_count/$total_count configurations"
        
        if [[ $success_count -eq $total_count ]]; then
            log_success "All configurations synced successfully!"
        else
            log_warning "Some configurations failed to sync. Check output above."
            exit 1
        fi
        
        if [[ -d "$BACKUP_DIR" ]]; then
            show_backup_stats
        fi
    fi
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Verbose mode shows detailed operation logs: `./sync-configs.sh --verbose pull`
- [ ] Quiet mode suppresses non-essential output: `./sync-configs.sh --quiet pull`
- [ ] Timestamp option works correctly: Compare output with/without `--no-timestamp`
- [ ] Conflicting options detected: Test `--verbose --quiet` combination

#### Manual Verification:
- [ ] Progress indicators work during multi-config operations
- [ ] Log levels (INFO, WARNING, ERROR, SUCCESS) display correctly
- [ ] Timestamps are formatted consistently and accurately
- [ ] Error messages are clear and actionable
- [ ] Help text is comprehensive and up-to-date

---

## Phase 5: Rollback Functionality

### Overview
Add the ability to easily restore from specific backups, providing safety net for failed operations.

**Dependencies**: Phase 4 (requires logging system for rollback operation feedback)

### Changes Required:

#### 1. Add Rollback Functions
**File**: `sync-configs.sh`
**Location**: After logging functions

```bash
# List available backups for rollback
list_available_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "No backup directory found"
        return 1
    fi
    
    local backup_files=()
    while IFS= read -r backup_file; do
        if [[ -n "$backup_file" ]]; then
            backup_files+=("$backup_file")
        fi
    done < <(list_backup_files)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_info "No backups found"
        return 1
    fi
    
    log_info "Available backups (newest first):"
    for ((i=${#backup_files[@]}-1; i>=0; i--)); do
        local backup_file="${backup_files[i]}"
        local backup_name=$(basename "$backup_file")
        local timestamp=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null || echo "unknown")
        local size="unknown"
        
        if [[ -f "$backup_file" ]]; then
            size=$(stat -f%z "$backup_file" 2>/dev/null | awk '{printf "%.1fKB", $1/1024}' || echo "unknown")
        elif [[ -d "$backup_file" ]]; then
            size=$(du -sh "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
        fi
        
        printf "  %-40s %s (%s)\n" "$backup_name" "$timestamp" "$size"
    done
}

# Parse backup filename to extract metadata
parse_backup_name() {
    local backup_name="$1"
    local config_name=""
    local location=""
    local timestamp=""
    
    # Expected format: configname_location_YYYYMMDD_HHMMSS
    if [[ "$backup_name" =~ ^(.+)_(system|repo)_([0-9]{8}_[0-9]{6})$ ]]; then
        config_name="${BASH_REMATCH[1]}"
        location="${BASH_REMATCH[2]}"
        timestamp="${BASH_REMATCH[3]}"
        
        echo "$config_name:$location:$timestamp"
        return 0
    fi
    
    log_error "Invalid backup name format: $backup_name"
    return 1
}

# Find original path for a backup
find_original_path() {
    local config_name="$1"
    local location="$2"
    
    # Search through CONFIG_MAPPINGS to find the matching config
    for mapping in "${CONFIG_MAPPINGS[@]}"; do
        IFS=':' read -r name system_path repo_path type <<< "$mapping"
        if [[ "$name" == "$config_name" ]]; then
            if [[ "$location" == "system" ]]; then
                echo "$system_path"
                return 0
            elif [[ "$location" == "repo" ]]; then
                echo "$repo_path"
                return 0
            fi
        fi
    done
    
    log_error "Could not find original path for config: $config_name"
    return 1
}

# Perform rollback operation
rollback_from_backup() {
    local backup_path="$1"
    local backup_name=$(basename "$backup_path")
    
    log_info "Rolling back from backup: $backup_name"
    
    # Parse backup metadata
    local backup_info
    if ! backup_info=$(parse_backup_name "$backup_name"); then
        return 1
    fi
    
    IFS=':' read -r config_name location timestamp <<< "$backup_info"
    
    # Find original path
    local original_path
    if ! original_path=$(find_original_path "$config_name" "$location"); then
        return 1
    fi
    
    log_verbose "Config: $config_name, Location: $location, Timestamp: $timestamp"
    log_verbose "Restoring to: $original_path"
    
    # Verify backup exists and is readable
    if [[ ! -e "$backup_path" ]]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi
    
    if [[ ! -r "$backup_path" ]]; then
        log_error "Cannot read backup: $backup_path"
        return 1
    fi
    
    # Create a backup of current state before rollback
    if [[ -e "$original_path" ]]; then
        log_verbose "Creating backup of current state before rollback"
        if ! create_backup "$original_path" "${config_name}_${location}_prerollback"; then
            log_error "Failed to backup current state, aborting rollback"
            return 1
        fi
    fi
    
    # Perform the rollback
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore: $backup_path -> $original_path"
        if [[ -d "$backup_path" ]]; then
            log_info "[DRY-RUN] Would remove existing directory: $original_path"
            log_info "[DRY-RUN] Would copy directory: $backup_path -> $original_path"
        else
            log_info "[DRY-RUN] Would copy file: $backup_path -> $original_path"
        fi
    else
        if [[ -d "$backup_path" ]]; then
            log_verbose "Restoring directory: $backup_path -> $original_path"
            if ! rm -rf "$original_path" 2>/dev/null; then
                log_error "Failed to remove existing directory: $original_path"
                return 1
            fi
            if ! mkdir -p "$(dirname "$original_path")"; then
                log_error "Failed to create parent directory for: $original_path"
                return 1
            fi
            if ! cp -r "$backup_path" "$original_path"; then
                log_error "Failed to restore directory: $backup_path -> $original_path"
                return 1
            fi
        else
            log_verbose "Restoring file: $backup_path -> $original_path"
            if ! mkdir -p "$(dirname "$original_path")"; then
                log_error "Failed to create parent directory for: $original_path"
                return 1
            fi
            if ! cp "$backup_path" "$original_path"; then
                log_error "Failed to restore file: $backup_path -> $original_path"
                return 1
            fi
        fi
        
        log_success "Rollback completed: $config_name restored from $backup_name"
    fi
    
    return 0
}

# Interactive rollback selection
interactive_rollback() {
    log_info "=== Interactive Rollback ==="
    
    if ! list_available_backups; then
        return 1
    fi
    
    echo ""
    read -p "Enter backup name to restore from (or 'cancel' to abort): " backup_name
    
    if [[ "$backup_name" == "cancel" ]] || [[ -z "$backup_name" ]]; then
        log_info "Rollback cancelled"
        return 0
    fi
    
    local backup_path="$BACKUP_DIR/$backup_name"
    if [[ ! -e "$backup_path" ]]; then
        log_error "Backup not found: $backup_name"
        return 1
    fi
    
    # Show what will be restored
    local backup_info
    if backup_info=$(parse_backup_name "$backup_name"); then
        IFS=':' read -r config_name location timestamp <<< "$backup_info"
        local original_path
        if original_path=$(find_original_path "$config_name" "$location"); then
            log_info "This will restore:"
            log_info "  Config: $config_name"
            log_info "  Location: $location"
            log_info "  Target: $original_path"
            log_info "  Backup timestamp: $timestamp"
            echo ""
            read -p "Are you sure? (y/N): " confirm
            
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                rollback_from_backup "$backup_path"
            else
                log_info "Rollback cancelled"
            fi
        fi
    fi
}

# Rollback specific config to latest backup
rollback_config() {
    local config_name="$1"
    local location="${2:-system}"  # Default to system
    
    log_info "Rolling back $config_name ($location) to latest backup..."
    
    # Find the most recent backup for this config
    local latest_backup=""
    local latest_timestamp=0
    
    if [[ -d "$BACKUP_DIR" ]]; then
        local pattern="${config_name}_${location}_[0-9]*_[0-9]*"
        while IFS= read -r -d '' backup_file; do
            local backup_name=$(basename "$backup_file")
            local timestamp_str=""
            
            if [[ "$backup_name" =~ _([0-9]{8}_[0-9]{6})$ ]]; then
                timestamp_str="${BASH_REMATCH[1]}"
                # Convert to comparable format (remove underscores)
                local comparable_timestamp="${timestamp_str//_/}"
                
                if [[ $comparable_timestamp -gt $latest_timestamp ]]; then
                    latest_timestamp=$comparable_timestamp
                    latest_backup="$backup_file"
                fi
            fi
        done < <(find "$BACKUP_DIR" -name "$pattern" -print0 2>/dev/null)
    fi
    
    if [[ -z "$latest_backup" ]]; then
        log_error "No backups found for config: $config_name ($location)"
        return 1
    fi
    
    log_info "Found latest backup: $(basename "$latest_backup")"
    rollback_from_backup "$latest_backup"
}
```

#### 2. Update usage Function for Rollback Commands
**File**: `sync-configs.sh`
**Replace usage function**

```bash
usage() {
    echo "Usage: $0 [options] {pull|push|backup-stats|backup-cleanup|rollback|list-backups}"
    echo ""
    echo "Operations:"
    echo "  pull            - Copy configs from system to repository"
    echo "  push            - Copy configs from repository to system"
    echo "  backup-stats    - Show backup statistics and disk usage"
    echo "  backup-cleanup  - Clean up old backups based on retention policy"
    echo "  rollback        - Interactive rollback from available backups"
    echo "  list-backups    - List all available backups"
    echo ""
    echo "Rollback Operations:"
    echo "  rollback [backup-name]     - Restore from specific backup"
    echo "  rollback-config <config>   - Restore config to latest backup"
    echo ""
    echo "Options:"
    echo "  --dry-run       - Preview operations without making changes"
    echo "  -v, --verbose   - Show detailed operation information"
    echo "  -q, --quiet     - Minimize output (errors only)"
    echo "  --no-timestamp  - Disable timestamps in log output"
    echo "  -h, --help      - Show this help message"
    echo ""
    echo "Configurations managed:"
    echo "  - Claude config (claude.md, agents/, commands/ from ~/.claude/)"
    echo "  - Tmux config (~/.tmux.conf)"
    echo "  - Ghostty config (~/Library/Application Support/com.mitchellh.ghostty/config)"
    echo ""
    echo "Examples:"
    echo "  $0 pull                                    # Sync from system to repo"
    echo "  $0 --dry-run --verbose push               # Preview push with details"
    echo "  $0 rollback                               # Interactive rollback"
    echo "  $0 rollback claude-md_system_20240107_143022  # Specific rollback"
    echo "  $0 rollback-config claude-md              # Restore claude-md to latest backup"
    echo "  $0 list-backups                           # Show available backups"
    echo ""
    echo "Backup Configuration:"
    echo "  Retention: $BACKUP_RETENTION_DAYS days"
    echo "  Max count: $BACKUP_MAX_COUNT files"
    echo "  Location: $BACKUP_DIR"
}
```

#### 3. Update main Function for Rollback Commands
**File**: `sync-configs.sh`
**Update argument parsing and command handling**

```bash
main() {
    local mode=""
    local rollback_target=""
    local config_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --no-timestamp)
                SHOW_TIMESTAMPS=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            pull|push|backup-stats|backup-cleanup|list-backups)
                mode="$1"
                shift
                ;;
            rollback)
                mode="rollback"
                shift
                # Check if specific backup name provided
                if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                    rollback_target="$1"
                    shift
                fi
                ;;
            rollback-config)
                mode="rollback-config"
                shift
                # Require config name
                if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                    config_name="$1"
                    shift
                else
                    log_error "rollback-config requires a config name"
                    usage
                    exit 1
                fi
                ;;
            *)
                log_error "Unknown argument '$1'"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate conflicting options
    if [[ "$VERBOSE" == "true" ]] && [[ "$QUIET" == "true" ]]; then
        log_error "Cannot use --verbose and --quiet together"
        exit 1
    fi
    
    # Validate required mode argument
    if [[ -z "$mode" ]]; then
        log_error "Mode is required"
        usage
        exit 1
    fi
    
    # Handle backup and rollback management commands
    case "$mode" in
        backup-stats)
            log_info "=== Backup Statistics ==="
            show_backup_stats
            return 0
            ;;
        backup-cleanup)
            log_info "=== Backup Cleanup ==="
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "DRY-RUN mode - no backups will actually be removed"
            fi
            cleanup_old_backups
            return 0
            ;;
        list-backups)
            list_available_backups
            return 0
            ;;
        rollback)
            if [[ -n "$rollback_target" ]]; then
                # Specific backup rollback
                local backup_path="$BACKUP_DIR/$rollback_target"
                if [[ ! -e "$backup_path" ]]; then
                    log_error "Backup not found: $rollback_target"
                    exit 1
                fi
                rollback_from_backup "$backup_path"
            else
                # Interactive rollback
                interactive_rollback
            fi
            return 0
            ;;
        rollback-config)
            rollback_config "$config_name"
            return 0
            ;;
    esac
    
    # Rest of sync operations remain the same...
    # Display mode information for sync operations
    log_info "=== Config Sync Tool ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Mode: $mode (DRY-RUN - no changes will be made)"
    else
        log_info "Mode: $mode"
    fi
    log_info "Repository: $SCRIPT_DIR"
    if [[ "$VERBOSE" == "true" ]]; then
        log_verbose "Backup directory: $BACKUP_DIR"
        log_verbose "Retention policy: $BACKUP_RETENTION_DAYS days, max $BACKUP_MAX_COUNT files"
    fi
    
    # Validate all mappings before starting sync
    validate_all_mappings
    
    local success_count=0
    local total_count=${#CONFIG_MAPPINGS[@]}
    
    for i in "${!CONFIG_MAPPINGS[@]}"; do
        local mapping="${CONFIG_MAPPINGS[i]}"
        show_progress $((i + 1)) $total_count "Processing configurations..."
        
        IFS=':' read -r name system_path repo_path type <<< "$mapping"
        if sync_config "$name" "$system_path" "$repo_path" "$type" "$mode"; then
            ((success_count++))
        fi
        
        if [[ "$QUIET" != "true" ]]; then
            echo ""  # Add spacing between configs
        fi
    done
    
    # Run automatic backup cleanup after successful sync operations
    if [[ $success_count -gt 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_info "=== Automatic Backup Cleanup ==="
        cleanup_old_backups
    fi
    
    # Final summary
    log_info "=== Sync Summary ==="
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN completed: $success_count/$total_count configurations would be synced"
        log_success "No actual changes were made. Use without --dry-run to execute."
    else
        log_info "Successful: $success_count/$total_count configurations"
        
        if [[ $success_count -eq $total_count ]]; then
            log_success "All configurations synced successfully!"
        else
            log_warning "Some configurations failed to sync. Check output above."
            exit 1
        fi
        
        if [[ -d "$BACKUP_DIR" ]]; then
            show_backup_stats
        fi
    fi
}
```

### Success Criteria:

#### Automated Verification:
- [ ] List backups shows all available backups: `./sync-configs.sh list-backups`
- [ ] Rollback from specific backup works: Create backup, modify config, rollback, verify restoration
- [ ] Config-specific rollback works: `./sync-configs.sh rollback-config claude-md`
- [ ] Dry-run rollback doesn't modify files: `./sync-configs.sh --dry-run rollback <backup>`

#### Manual Verification:
- [ ] Interactive rollback provides clear prompts and confirmation
- [ ] Rollback creates backup of current state before restoring
- [ ] Error handling works for invalid backup names
- [ ] Backup parsing correctly extracts config name, location, and timestamp
- [ ] Rollback operations are logged with appropriate detail levels

---

## Phase 6: Cross-Platform Compatibility

### Overview
Add support for different operating systems and resolve platform-specific path issues.

**Dependencies**: Phase 5 (requires all core functionality for comprehensive cross-platform testing)

### Changes Required:

#### 1. Add Platform Detection and Path Resolution
**File**: `sync-configs.sh`
**Lines**: After SHOW_TIMESTAMPS

```bash
# Platform detection and configuration
detect_platform() {
    local platform=""
    local os_name=$(uname -s)
    
    case "$os_name" in
        Darwin*)
            platform="macos"
            ;;
        Linux*)
            platform="linux"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            platform="windows"
            ;;
        *)
            platform="unknown"
            ;;
    esac
    
    echo "$platform"
}

PLATFORM=$(detect_platform)
```

#### 2. Add Cross-Platform Path Resolution Functions
**File**: `sync-configs.sh`
**Location**: After platform detection

```bash
# Cross-platform path resolution
resolve_home_directory() {
    if [[ "$PLATFORM" == "windows" ]]; then
        echo "${USERPROFILE:-${HOME}}"
    else
        echo "${HOME}"
    fi
}

resolve_application_support() {
    local app_name="$1"
    local home_dir=$(resolve_home_directory)
    
    case "$PLATFORM" in
        macos)
            echo "$home_dir/Library/Application Support/$app_name"
            ;;
        linux)
            echo "${XDG_DATA_HOME:-$home_dir/.local/share}/$app_name"
            ;;
        windows)
            echo "${APPDATA}/$app_name"
            ;;
        *)
            echo "$home_dir/.local/share/$app_name"
            ;;
    esac
}

resolve_config_directory() {
    local app_name="$1"
    local home_dir=$(resolve_home_directory)
    
    case "$PLATFORM" in
        macos)
            echo "$home_dir/.config/$app_name"
            ;;
        linux)
            echo "${XDG_CONFIG_HOME:-$home_dir/.config}/$app_name"
            ;;
        windows)
            echo "${APPDATA}/$app_name"
            ;;
        *)
            echo "$home_dir/.config/$app_name"
            ;;
    esac
}

# Get platform-specific claude directory
get_claude_directory() {
    local home_dir=$(resolve_home_directory)
    echo "$home_dir/.claude"
}

# Get platform-specific ghostty config path
get_ghostty_config_path() {
    case "$PLATFORM" in
        macos)
            echo "$(resolve_application_support "com.mitchellh.ghostty")/config"
            ;;
        linux)
            echo "$(resolve_config_directory "ghostty")/config"
            ;;
        windows)
            echo "$(resolve_application_support "ghostty")/config"
            ;;
        *)
            echo "$(resolve_config_directory "ghostty")/config"
            ;;
    esac
}
```

#### 3. Update CONFIG_MAPPINGS for Cross-Platform Support
**File**: `sync-configs.sh`
**Replace CONFIG_MAPPINGS array**

```bash
# Platform-aware configuration mappings
setup_config_mappings() {
    local home_dir=$(resolve_home_directory)
    local claude_dir=$(get_claude_directory)
    local ghostty_config=$(get_ghostty_config_path)
    
    CONFIG_MAPPINGS=(
        "claude-md:$claude_dir/claude.md:$SCRIPT_DIR/claude/claude.md:file"
        "claude-agents:$claude_dir/agents:$SCRIPT_DIR/claude/agents:dir"
        "claude-commands:$claude_dir/commands:$SCRIPT_DIR/claude/commands:dir"
        "tmux:$home_dir/.tmux.conf:$SCRIPT_DIR/tmux.conf:file"
        "ghostty:$ghostty_config:$SCRIPT_DIR/ghostty-config:file"
    )
    
    # Add platform-specific configurations
    case "$PLATFORM" in
        linux)
            # Add Linux-specific configs here if needed
            ;;
        windows)
            # Add Windows-specific configs here if needed
            ;;
    esac
    
    log_verbose "Initialized ${#CONFIG_MAPPINGS[@]} configuration mappings for platform: $PLATFORM"
}
```

#### 4. Add Cross-Platform File Operations
**File**: `sync-configs.sh`
**Location**: After path resolution functions

```bash
# Cross-platform file operations
safe_copy_file() {
    local source="$1"
    local target="$2"
    
    # Create parent directory
    if ! mkdir -p "$(dirname "$target")"; then
        log_error "Failed to create parent directory for: $target"
        return 1
    fi
    
    # Platform-specific copy operations
    case "$PLATFORM" in
        windows)
            # Use Windows-compatible copy on MinGW/MSYS
            if command -v cp >/dev/null; then
                cp "$source" "$target"
            else
                # Fallback to Windows copy command
                copy "$(cygpath -w "$source")" "$(cygpath -w "$target")" >/dev/null
            fi
            ;;
        *)
            cp "$source" "$target"
            ;;
    esac
}

safe_copy_directory() {
    local source="$1"
    local target="$2"
    
    # Remove existing target
    if ! rm -rf "$target" 2>/dev/null; then
        log_error "Failed to remove existing directory: $target"
        return 1
    fi
    
    # Create parent directory
    if ! mkdir -p "$(dirname "$target")"; then
        log_error "Failed to create parent directory for: $target"
        return 1
    fi
    
    # Platform-specific directory copy
    case "$PLATFORM" in
        windows)
            if command -v cp >/dev/null; then
                cp -r "$source" "$target"
            else
                # Use Windows xcopy as fallback
                xcopy "$(cygpath -w "$source")" "$(cygpath -w "$target")" /E /I /Q >/dev/null
            fi
            ;;
        *)
            cp -r "$source" "$target"
            ;;
    esac
}

# Get file modification time in consistent format across platforms
get_file_mtime() {
    local file_path="$1"
    
    case "$PLATFORM" in
        macos)
            stat -f "%m" "$file_path" 2>/dev/null
            ;;
        linux)
            stat -c "%Y" "$file_path" 2>/dev/null
            ;;
        windows)
            # Windows stat might not be available, use ls as fallback
            if command -v stat >/dev/null; then
                stat -c "%Y" "$file_path" 2>/dev/null
            else
                # Fallback to a basic timestamp
                date +%s 2>/dev/null
            fi
            ;;
        *)
            stat -c "%Y" "$file_path" 2>/dev/null || date +%s
            ;;
    esac
}

# Get file size in bytes across platforms
get_file_size() {
    local file_path="$1"
    
    case "$PLATFORM" in
        macos)
            stat -f "%z" "$file_path" 2>/dev/null
            ;;
        linux)
            stat -c "%s" "$file_path" 2>/dev/null
            ;;
        windows)
            if command -v stat >/dev/null; then
                stat -c "%s" "$file_path" 2>/dev/null
            else
                # Windows fallback
                wc -c < "$file_path" 2>/dev/null
            fi
            ;;
        *)
            stat -c "%s" "$file_path" 2>/dev/null || wc -c < "$file_path" 2>/dev/null
            ;;
    esac
}
```

#### 5. Update File Operations in sync_config Function
**File**: `sync-configs.sh`
**Replace copy operations in sync_config function**

```bash
sync_config() {
    local name="$1"
    local system_path="$2"
    local repo_path="$3"
    local type="$4"
    local mode="$5"
    
    log_info "Syncing $name config..."
    log_verbose "  Mode: $mode, Type: $type, Platform: $PLATFORM"
    
    # Validate paths before proceeding
    if ! validate_paths "$system_path" "$repo_path" "$mode"; then
        log_warning "Skipping $name due to validation errors"
        return 1
    fi
    
    if [[ "$mode" == "pull" ]]; then
        show_dry_run_details "PULL" "$system_path" "$repo_path" "$type"
        
        # Create backup if target exists
        if [[ -e "$repo_path" ]]; then
            log_verbose "Target exists, creating backup first"
            if ! create_backup "$repo_path" "${name}_repo"; then
                log_error "Failed to create backup for $repo_path"
                return 1
            fi
        fi
        
        # Perform copy operation using platform-safe functions
        if [[ "$type" == "dir" ]]; then
            log_verbose "Copying directory: $system_path -> $repo_path"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would copy directory: $system_path -> $repo_path"
            else
                if ! safe_copy_directory "$system_path" "$repo_path"; then
                    log_error "Failed to copy directory: $system_path -> $repo_path"
                    return 1
                fi
            fi
        else
            log_verbose "Copying file: $system_path -> $repo_path"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would copy file: $system_path -> $repo_path"
            else
                if ! safe_copy_file "$system_path" "$repo_path"; then
                    log_error "Failed to copy file: $system_path -> $repo_path"
                    return 1
                fi
            fi
        fi
        
    elif [[ "$mode" == "push" ]]; then
        show_dry_run_details "PUSH" "$repo_path" "$system_path" "$type"
        
        # Create backup if target exists
        if [[ -e "$system_path" ]]; then
            log_verbose "Target exists, creating backup first"
            if ! create_backup "$system_path" "${name}_system"; then
                log_error "Failed to create backup for $system_path"
                return 1
            fi
        fi
        
        # Perform copy operation using platform-safe functions
        if [[ "$type" == "dir" ]]; then
            log_verbose "Copying directory: $repo_path -> $system_path"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would copy directory: $repo_path -> $system_path"
            else
                if ! safe_copy_directory "$repo_path" "$system_path"; then
                    log_error "Failed to copy directory: $repo_path -> $system_path"
                    return 1
                fi
            fi
        else
            log_verbose "Copying file: $repo_path -> $system_path"
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would copy file: $repo_path -> $system_path"
            else
                if ! safe_copy_file "$repo_path" "$system_path"; then
                    log_error "Failed to copy file: $repo_path -> $system_path"
                    return 1
                fi
            fi
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would complete: $name config sync"
    else
        log_success "$name config synced successfully"
    fi
    return 0
}
```

#### 6. Update Backup Functions for Cross-Platform Support
**File**: `sync-configs.sh`
**Replace backup-related functions**

```bash
list_backup_files() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        return 0
    fi
    
    # Use platform-appropriate find and sort
    case "$PLATFORM" in
        windows)
            # Windows might have limited find capabilities
            if command -v find >/dev/null && command -v sort >/dev/null; then
                find "$BACKUP_DIR" -type f -name "*_[0-9]*_[0-9]*" 2>/dev/null | sort
            else
                # Fallback to basic listing
                ls "$BACKUP_DIR"/*_[0-9]*_[0-9]* 2>/dev/null | sort
            fi
            ;;
        *)
            find "$BACKUP_DIR" -type f -name "*_[0-9]*_[0-9]*" -exec stat -c "%Y %n" {} \; 2>/dev/null | \
                sort -n | \
                cut -d' ' -f2-
            ;;
    esac
}

show_backup_stats() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backups found"
        return 0
    fi
    
    local backup_files=()
    while IFS= read -r backup_file; do
        if [[ -n "$backup_file" ]]; then
            backup_files+=("$backup_file")
        fi
    done < <(list_backup_files)
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        echo "No backups found"
        return 0
    fi
    
    local total_size=0
    for backup_file in "${backup_files[@]}"; do
        if [[ -f "$backup_file" ]]; then
            local size=$(get_file_size "$backup_file")
            total_size=$((total_size + size))
        elif [[ -d "$backup_file" ]]; then
            # Platform-specific directory size calculation
            case "$PLATFORM" in
                macos)
                    local size=$(du -sk "$backup_file" 2>/dev/null | cut -f1 || echo "0")
                    total_size=$((total_size + size * 1024))
                    ;;
                linux)
                    local size=$(du -sb "$backup_file" 2>/dev/null | cut -f1 || echo "0")
                    total_size=$((total_size + size))
                    ;;
                windows)
                    # Windows du might not be available
                    if command -v du >/dev/null; then
                        local size=$(du -sk "$backup_file" 2>/dev/null | cut -f1 || echo "0")
                        total_size=$((total_size + size * 1024))
                    fi
                    ;;
                *)
                    local size=$(du -sb "$backup_file" 2>/dev/null | cut -f1 || echo "0")
                    total_size=$((total_size + size))
                    ;;
            esac
        fi
    done
    
    local total_mb=$((total_size / 1024 / 1024))
    echo "Backup Statistics:"
    echo "  Platform: $PLATFORM"
    echo "  Total backups: ${#backup_files[@]}"
    echo "  Total size: ${total_mb}MB"
    echo "  Retention: $BACKUP_RETENTION_DAYS days (max $BACKUP_MAX_COUNT files)"
    echo "  Location: $BACKUP_DIR"
}
```

#### 7. Update main Function Initialization
**File**: `sync-configs.sh`
**Add setup call at beginning of main function**

```bash
main() {
    # Initialize platform-specific configuration mappings
    setup_config_mappings
    
    local mode=""
    local rollback_target=""
    local config_name=""
    
    # Rest of main function remains the same...
```

#### 8. Update usage Function with Platform Information
**File**: `sync-configs.sh`
**Add platform info to usage output**

```bash
usage() {
    echo "Usage: $0 [options] {pull|push|backup-stats|backup-cleanup|rollback|list-backups}"
    echo ""
    echo "Platform: $PLATFORM"
    echo ""
    # Rest of usage remains the same...
```

### Success Criteria:

#### Automated Verification:
- [ ] Platform detection works correctly: Test on macOS, Linux, Windows
- [ ] Path resolution adapts to platform: Verify correct paths for each OS
- [ ] File operations work cross-platform: Test copy operations on different systems
- [ ] Backup statistics show platform information: Check platform field in output

#### Manual Verification:
- [ ] Ghostty config path resolves correctly on each platform
- [ ] XDG directory standards respected on Linux
- [ ] Windows paths work with spaces and special characters
- [ ] Application Support directories used correctly on macOS
- [ ] Script runs without errors on different bash versions

---

## Testing Strategy

### Unit Testing Approach
Since this is a bash script, testing will be primarily integration-based with some unit testing of individual functions.

#### Test Scenarios per Phase:
1. **Phase 1**: Validation functions, error handling, backup integrity
2. **Phase 2**: Dry-run functionality, argument parsing
3. **Phase 3**: Backup retention, cleanup algorithms  
4. **Phase 4**: Logging levels, verbosity controls
5. **Phase 5**: Rollback operations, backup parsing
6. **Phase 6**: Platform detection, path resolution

### Integration Testing
- Full sync operations (pull/push) on each platform
- Backup and restore cycles
- Error recovery scenarios
- Large file/directory handling
- Permission edge cases

### Manual Testing Checklist
- Cross-platform compatibility verification
- User experience with different verbosity levels
- Rollback scenarios under various failure conditions
- Backup cleanup with different retention policies

## Performance Considerations

- **Backup operations**: Large directories may take significant time
- **Path validation**: Minimize filesystem checks in validation phase
- **Cleanup operations**: Use efficient find commands for backup cleanup
- **Progress indicators**: Only show for operations taking >2 seconds

## Migration Notes

- **Backward compatibility**: All existing sync operations must continue working
- **Configuration preservation**: Existing CONFIG_MAPPINGS format maintained
- **Backup location**: Keep using ~/.config-backups for consistency

## References

- Original research: `thoughts/shared/research/2025-09-07_05-03-05_sync-configs-analysis.md`
- Current implementation: `sync-configs.sh:1-132`  
- Industry standards: chezmoi, dotbot, GNU Stow patterns analyzed

---

## Implementation Notes

Each phase builds incrementally on the previous phase, ensuring:
- **No breaking changes** to existing functionality  
- **Comprehensive testing** before moving to next phase
- **Rollback capability** if any phase introduces issues
- **Documentation updates** as features are added

The plan prioritizes high-impact, low-effort improvements first, then progressively adds more advanced features. This approach ensures the script remains reliable and useful throughout the enhancement process.