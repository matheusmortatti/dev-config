#!/bin/bash

# Enhanced error handling - catch undefined variables and pipe failures
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config-backups"

# Global dry-run flag
DRY_RUN=false

# Backup configuration
BACKUP_RETENTION_DAYS=30
BACKUP_MAX_COUNT=100

# Verbosity and output configuration
VERBOSE=false
QUIET=false
SHOW_TIMESTAMPS=true

CONFIG_MAPPINGS=(
    "claude-md:$HOME/.claude/claude.md:$SCRIPT_DIR/claude/claude.md:file"
    "claude-agents:$HOME/.claude/agents:$SCRIPT_DIR/claude/agents:dir"
    "claude-commands:$HOME/.claude/commands:$SCRIPT_DIR/claude/commands:dir"
    "tmux:$HOME/.tmux.conf:$SCRIPT_DIR/tmux.conf:file"
    "ghostty:$HOME/Library/Application Support/com.mitchellh.ghostty/config:$SCRIPT_DIR/ghostty-config:file"
)

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
        local repo_dir
        repo_dir="$(dirname "$repo_path")"
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
        local system_dir
        system_dir="$(dirname "$system_path")"
        if [[ ! -w "$system_dir" ]] && [[ ! -w "$(dirname "$system_dir")" ]]; then
            log_error "No write permission for system path: $system_dir"
            return 1
        fi
        log_verbose "  ✓ Push validation passed"
    fi
    
    return 0
}

# Validate all mappings at startup
validate_all_mappings() {
    local errors=0
    log_info "Validating configuration mappings..."
    
    for mapping in "${CONFIG_MAPPINGS[@]}"; do
        if ! validate_mapping_format "$mapping"; then
            ((errors++))
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        log_error "Found $errors invalid mapping(s). Please fix CONFIG_MAPPINGS."
        exit 1
    fi
    
    log_success "All mappings validated successfully"
}

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
            local file_count
            file_count=$(find "$source" -type f | wc -l)
            echo "    Files to copy: $file_count"
        else
            local size
            size=$(stat -f%z "$source" 2>/dev/null || echo "unknown")
            echo "    File size: $size bytes"
        fi
    fi
    
    if [[ -e "$target" ]]; then
        echo "    Target exists: Will create backup first"
    else
        echo "    Target exists: No (new file/directory)"
    fi
}

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
    local all_candidates=()
    
    # Add old backups to candidates list
    if [[ ${#old_backups[@]} -gt 0 ]]; then
        all_candidates+=("${old_backups[@]}")
    fi
    
    # Add excess backups to candidates list  
    if [[ ${#excess_backups[@]} -gt 0 ]]; then
        all_candidates+=("${excess_backups[@]}")
    fi
    
    # Deduplicate the combined list
    if [[ ${#all_candidates[@]} -gt 0 ]]; then
        for backup in "${all_candidates[@]}"; do
        local found=false
        if [[ ${#cleanup_candidates[@]} -gt 0 ]]; then
            for existing in "${cleanup_candidates[@]}"; do
                if [[ "$existing" == "$backup" ]]; then
                    found=true
                    break
                fi
            done
        fi
        if [[ "$found" == "false" ]]; then
            cleanup_candidates+=("$backup")
        fi
        done
    fi
    
    if [[ ${#cleanup_candidates[@]} -eq 0 ]]; then
        echo "  ✓ No old backups to clean up"
        return 0
    fi
    
    echo "  Found ${#cleanup_candidates[@]} backup(s) to clean up"
    for backup_file in "${cleanup_candidates[@]}"; do
        local backup_name
        backup_name=$(basename "$backup_file")
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
            local size
            size=$(stat -f%z "$backup_file" 2>/dev/null || echo "0")
            total_size=$((total_size + size))
        elif [[ -d "$backup_file" ]]; then
            local size
            size=$(du -sk "$backup_file" 2>/dev/null | cut -f1 || echo "0")
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
        local backup_name
        backup_name=$(basename "$backup_file")
        local timestamp
        timestamp=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null || echo "unknown")
        local size="unknown"
        
        if [[ -f "$backup_file" ]]; then
            size=$(stat -f%z "$backup_file" 2>/dev/null | awk '{printf "%.1fKB", $1/1024}' || echo "unknown")
        elif [[ -d "$backup_file" ]]; then
            size=$(du -sh "$backup_file" 2>/dev/null | cut -f1 || echo "unknown")
        fi
        
        printf "  %-40s %s (%s)\\n" "$backup_name" "$timestamp" "$size"
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
    local backup_name
    backup_name=$(basename "$backup_path")
    
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
    local location="${2:-}"  # Optional location
    
    log_info "Rolling back $config_name to latest backup..."
    
    # Find the most recent backup for this config (check both system and repo if location not specified)
    local latest_backup=""
    local latest_timestamp=0
    local backup_location=""
    
    if [[ -d "$BACKUP_DIR" ]]; then
        # If location specified, only search that location
        local locations=()
        if [[ -n "$location" ]]; then
            locations=("$location")
        else
            # Search both system and repo backups
            locations=("system" "repo")
        fi
        
        for loc in "${locations[@]}"; do
            local pattern="${config_name}_${loc}_[0-9]*_[0-9]*"
            while IFS= read -r -d '' backup_file; do
                local backup_name
                backup_name=$(basename "$backup_file")
                local timestamp_str=""
                
                if [[ "$backup_name" =~ _([0-9]{8}_[0-9]{6})$ ]]; then
                    timestamp_str="${BASH_REMATCH[1]}"
                    # Convert to comparable format (remove underscores)
                    local comparable_timestamp="${timestamp_str//_/}"
                    
                    if [[ $comparable_timestamp -gt $latest_timestamp ]]; then
                        latest_timestamp=$comparable_timestamp
                        latest_backup="$backup_file"
                        backup_location="$loc"
                    fi
                fi
            done < <(find "$BACKUP_DIR" -name "$pattern" -print0 2>/dev/null)
        done
    fi
    
    if [[ -z "$latest_backup" ]]; then
        if [[ -n "$location" ]]; then
            log_error "No backups found for config: $config_name ($location)"
        else
            log_error "No backups found for config: $config_name"
        fi
        return 1
    fi
    
    log_info "Found latest backup: $(basename "$latest_backup") (location: $backup_location)"
    rollback_from_backup "$latest_backup"
}

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

create_backup() {
    local target="$1"
    local backup_name="$2"
    
    if [[ -e "$target" ]]; then
        local timestamp
        timestamp=$(date +"%Y%m%d_%H%M%S")
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
    
    # Mode-specific operations with enhanced error handling
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
            local repo_parent_dir
            repo_parent_dir="$(dirname "$repo_path")"
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$repo_parent_dir\""; then
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
            local system_parent_dir
            system_parent_dir="$(dirname "$system_path")"
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$system_parent_dir\""; then
                log_error "Failed to create parent directory for: $system_path"
                return 1
            fi
            if ! dry_run_execute "Copy directory" "cp -r \"$repo_path\" \"$system_path\""; then
                log_error "Failed to copy directory: $repo_path -> $system_path"
                return 1
            fi
        else
            log_verbose "Copying file: $repo_path -> $system_path"
            local system_parent_dir2
            system_parent_dir2="$(dirname "$system_path")"
            if ! dry_run_execute "Create parent directory" "mkdir -p \"$system_parent_dir2\""; then
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
        show_progress $((i + 1)) "$total_count" "Processing configurations..."
        
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

main "$@"