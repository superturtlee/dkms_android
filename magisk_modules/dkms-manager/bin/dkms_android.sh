#!/system/bin/sh
# Android DKMS - WebUI Backend for KernelSU
# Based on dkms_android.sh, extended with WebUI API

MAGISK_MODULES_DIR="/data/adb/modules"
MODDIR="${MODDIR:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
RUNTIME_DIR="$MODDIR/tmp"
DKMS_LOG="$RUNTIME_DIR/dkms.log"
STATE_FILE="$RUNTIME_DIR/state"
MESSAGE_FILE="$RUNTIME_DIR/message"
PID_FILE="$RUNTIME_DIR/task.pid"
LOCK_DIR="$RUNTIME_DIR/task.lock"

export PATH=/data/adb/ksu/bin:/data/adb/ap/bin:/system/bin:/system/xbin:$PATH

# --- Helpers ---

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
emit() { printf '%s' "$1" | tr '\n' '\t'; }

ensure_runtime() {
    mkdir -p "$RUNTIME_DIR"
    [ -f "$DKMS_LOG" ]     || : > "$DKMS_LOG"
    [ -f "$STATE_FILE" ]   || printf 'idle\n' > "$STATE_FILE"
    [ -f "$MESSAGE_FILE" ] || printf 'Idle\n' > "$MESSAGE_FILE"
}

write_state() {
    ensure_runtime
    printf '%s\n' "$1" > "$STATE_FILE"
    printf '%s\n' "$2" > "$MESSAGE_FILE"
}

log_info() {
    printf '[%s] [INFO] %s\n' "$(timestamp)" "$*" >> "$DKMS_LOG"
}

log_error() {
    printf '[%s] [ERROR] %s\n' "$(timestamp)" "$*" >> "$DKMS_LOG"
}

log_warn() {
    printf '[%s] [WARN] %s\n' "$(timestamp)" "$*" >> "$DKMS_LOG"
}

parse_cfg() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    grep -m1 "^${key}=" "$file" | cut -d'=' -f2-
}

# --- Module Discovery ---

find_first_toolchain() {
    for moddir in "$MAGISK_MODULES_DIR"/*/; do
        [ -d "$moddir" ] || continue
        [ -f "${moddir}disable" ] && continue
        if [ -f "${moddir}toolchain.cfg" ] && [ -f "${moddir}setuptoolchain.sh" ]; then
            echo "$moddir"
            return 0
        fi
    done
    return 1
}

find_header_module() {
    local target_kver="$1"
    for moddir in "$MAGISK_MODULES_DIR"/*/; do
        [ -d "$moddir" ] || continue
        [ -f "${moddir}disable" ] && continue
        if [ -f "${moddir}header.cfg" ] && [ -d "${moddir}header" ]; then
            local kver
            kver=$(parse_cfg "${moddir}header.cfg" "KERNEL_VERSION")
            if [ "$kver" = "$target_kver" ]; then
                echo "$moddir"
                return 0
            fi
        fi
    done
    return 1
}

find_kmod_by_name() {
    local target="$1"
    for moddir in "$MAGISK_MODULES_DIR"/*/; do
        [ -d "$moddir" ] || continue
        if [ -f "${moddir}kmodinfo.cfg" ]; then
            local name
            name=$(parse_cfg "${moddir}kmodinfo.cfg" "NAME")
            if [ "$name" = "$target" ]; then
                echo "$moddir"
                return 0
            fi
        fi
    done
    return 1
}

# --- List ---
# Output format per line (pipe-delimited):
#   H|module-id|kernel-version|disabled
#   T|module-id|toolchain-name|disabled
#   K|module-id|name|version|built|built-kver|loaded|autoload|disabled

cmd_list() {
    local output=""
    local myid
    myid=$(basename "$MODDIR")

    for moddir in "$MAGISK_MODULES_DIR"/*/; do
        [ -d "$moddir" ] || continue
        local modid
        modid=$(basename "$moddir")
        [ "$modid" = "$myid" ] && continue

        local disabled="no"
        [ -f "${moddir}disable" ] && disabled="yes"

        if [ -f "${moddir}header.cfg" ] && [ -d "${moddir}header" ]; then
            local kver
            kver=$(parse_cfg "${moddir}header.cfg" "KERNEL_VERSION")
            [ -n "$kver" ] && output="${output}H|${modid}|${kver}|${disabled}
"
        fi

        if [ -f "${moddir}toolchain.cfg" ] && [ -f "${moddir}setuptoolchain.sh" ]; then
            local tcname
            tcname=$(parse_cfg "${moddir}toolchain.cfg" "TOOLCHAIN_NAME")
            [ -n "$tcname" ] && output="${output}T|${modid}|${tcname}|${disabled}
"
        fi

        if [ -f "${moddir}kmodinfo.cfg" ]; then
            local name version built bkver loaded autoload
            name=$(parse_cfg "${moddir}kmodinfo.cfg" "NAME")
            version=$(parse_cfg "${moddir}kmodinfo.cfg" "VERSION")
            [ -z "$name" ] && continue

            built="no"; bkver="-"
            if [ -f "${moddir}${name}.ko" ]; then
                built="yes"
                if [ -f "${moddir}currentbuild.inf" ]; then
                    bkver=$(parse_cfg "${moddir}currentbuild.inf" "MOD_KERNEL")
                    [ -z "$bkver" ] && bkver="-"
                fi
            fi

            loaded="no"
            lsmod 2>/dev/null | grep -q "^${name} " && loaded="yes"

            autoload="off"
            if [ "$disabled" = "no" ] && [ -f "${moddir}autoload" ]; then
                autoload="on"
            fi

            output="${output}K|${modid}|${name}|${version}|${built}|${bkver}|${loaded}|${autoload}|${disabled}
"
        fi
    done
    emit "$output"
}

# --- Build (foreground, called by bg process) ---

do_build() {
    local name="$1" force="$2"
    local moddir
    moddir=$(find_kmod_by_name "$name")

    if [ -z "$moddir" ]; then
        log_error "Module '$name' not found"
        write_state "error" "Module '$name' not found"
        return 1
    fi

    if [ ! -f "${moddir}build.sh" ]; then
        log_error "$name: missing build.sh"
        write_state "error" "$name: missing build.sh"
        return 1
    fi

    local NAME VERSION
    NAME=$(parse_cfg "${moddir}kmodinfo.cfg" "NAME")
    VERSION=$(parse_cfg "${moddir}kmodinfo.cfg" "VERSION")

    log_info "Building $NAME ($VERSION) ..."
    write_state "running" "Building $NAME ..."

    local tc_dir
    tc_dir=$(find_first_toolchain)
    if [ -z "$tc_dir" ]; then
        log_error "$NAME: no toolchain module found"
        write_state "error" "$NAME: no toolchain found"
        return 1
    fi

    local TOOLCHAIN_NAME
    TOOLCHAIN_NAME=$(parse_cfg "${tc_dir}toolchain.cfg" "TOOLCHAIN_NAME")
    log_info "$NAME: using toolchain $TOOLCHAIN_NAME"

    local KERNEL_VERSION header_dir
    if [ -f "${moddir}currentbuild.inf" ]; then
        local prev_kver
        prev_kver=$(parse_cfg "${moddir}currentbuild.inf" "MOD_KERNEL")
        if [ -n "$prev_kver" ]; then
            header_dir=$(find_header_module "$prev_kver")
            [ -n "$header_dir" ] && KERNEL_VERSION="$prev_kver"
        fi
    fi

    if [ -z "$KERNEL_VERSION" ]; then
        for hdir in "$MAGISK_MODULES_DIR"/*/; do
            [ -d "$hdir" ] || continue
            [ -f "${hdir}disable" ] && continue
            if [ -f "${hdir}header.cfg" ] && [ -d "${hdir}header" ]; then
                KERNEL_VERSION=$(parse_cfg "${hdir}header.cfg" "KERNEL_VERSION")
                header_dir="$hdir"
                break
            fi
        done
    fi

    if [ -z "$KERNEL_VERSION" ] || [ -z "$header_dir" ]; then
        log_error "$NAME: no kernel header module found"
        write_state "error" "$NAME: no headers found"
        return 1
    fi

    log_info "$NAME: kernel $KERNEL_VERSION"
    log_info "$NAME: headers at ${header_dir}header/"

    if [ "$force" != "1" ] && [ -f "${moddir}currentbuild.inf" ]; then
        local cur_kver
        cur_kver=$(parse_cfg "${moddir}currentbuild.inf" "MOD_KERNEL")
        if [ "$cur_kver" = "$KERNEL_VERSION" ] && [ -f "${moddir}${NAME}.ko" ]; then
            log_info "$NAME: already built for $KERNEL_VERSION, skipping"
            write_state "success" "$NAME: already up to date"
            return 0
        fi
    fi

    export KMODPATH="$moddir"
    export TOOLCHAIN_DIR="$tc_dir"
    if ! . "${tc_dir}setuptoolchain.sh"; then
        log_error "$NAME: toolchain setup failed"
        write_state "error" "$NAME: toolchain setup failed"
        return 1
    fi

    export KERNEL_VERSION TOOLCHAIN_NAME NAME VERSION

    cd "$moddir" || return 1
    write_state "running" "Compiling $NAME ..."

    if sh "${moddir}build.sh" >> "$DKMS_LOG" 2>&1; then
        if [ -f "${moddir}${NAME}.ko" ]; then
            echo "MOD_KERNEL=$KERNEL_VERSION" > "${moddir}currentbuild.inf"
            log_info "$NAME: build succeeded"
            write_state "success" "$NAME: build succeeded"
            return 0
        else
            log_error "$NAME: build.sh succeeded but ${NAME}.ko not found"
            write_state "error" "$NAME: .ko not produced"
            return 1
        fi
    else
        log_error "$NAME: build failed"
        write_state "error" "$NAME: build failed"
        return 1
    fi
}

do_build_all() {
    local force="$1"
    local total=0 current=0 success=0 fail=0

    for moddir in "$MAGISK_MODULES_DIR"/*/; do
        [ -d "$moddir" ] || continue
        [ -f "${moddir}disable" ] && continue
        [ -f "${moddir}kmodinfo.cfg" ] || continue
        total=$((total + 1))
    done

    if [ "$total" -eq 0 ]; then
        log_info "No kernel modules found"
        write_state "success" "No modules to build"
        return 0
    fi

    log_info "=== Build all ($total modules) ==="

    for moddir in "$MAGISK_MODULES_DIR"/*/; do
        [ -d "$moddir" ] || continue
        [ -f "${moddir}disable" ] && continue
        [ -f "${moddir}kmodinfo.cfg" ] || continue

        current=$((current + 1))
        local name
        name=$(parse_cfg "${moddir}kmodinfo.cfg" "NAME")
        [ -z "$name" ] && continue

        write_state "running" "Building ($current/$total): $name"
        if do_build "$name" "$force"; then
            success=$((success + 1))
        else
            fail=$((fail + 1))
        fi
    done

    if [ "$fail" -eq 0 ]; then
        write_state "success" "All done: $success/$total succeeded"
    else
        write_state "error" "Done: $success ok, $fail failed"
    fi
    log_info "Build complete: $success/$total succeeded, $fail failed"
}

# --- Background Task Management ---

current_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(tr -d '[:space:]' < "$PID_FILE")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$pid"
            return 0
        fi
        rm -f "$PID_FILE"
    fi
    return 1
}

cleanup_lock() { rm -rf "$LOCK_DIR"; rm -f "$PID_FILE"; }

cmd_start_task() {
    local action="$1" target="$2"
    ensure_runtime

    if current_pid >/dev/null 2>&1; then
        emit "BUSY=1"
        return 0
    fi

    : > "$DKMS_LOG"
    write_state "running" "Starting..."

    if command -v nohup >/dev/null 2>&1; then
        MODDIR="$MODDIR" nohup sh "$0" do-task "$action" "$target" >/dev/null 2>&1 &
    else
        MODDIR="$MODDIR" sh "$0" do-task "$action" "$target" </dev/null >/dev/null 2>&1 &
    fi

    sleep 0.5

    if current_pid >/dev/null 2>&1; then
        emit "STARTED=1"
    else
        local st=""
        [ -f "$STATE_FILE" ] && read -r st < "$STATE_FILE"
        case "$st" in
            success|error) emit "FINISHED=$st" ;;
            *) emit "STARTED=0" ;;
        esac
    fi
}

cmd_do_task() {
    local action="$1" target="$2"
    ensure_runtime

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log_error "A task is already running"
        return 1
    fi
    printf '%s\n' "$$" > "$PID_FILE"
    trap cleanup_lock EXIT INT TERM HUP

    case "$action" in
        build)       do_build "$target" ""  ;;
        rebuild)     do_build "$target" "1" ;;
        build-all)   do_build_all ""  ;;
        rebuild-all) do_build_all "1" ;;
        *) log_error "Unknown action: $action" ; write_state "error" "Unknown action" ;;
    esac
}

cmd_task_status() {
    ensure_runtime
    local running="0"
    current_pid >/dev/null 2>&1 && running="1"

    local st="" msg=""
    [ -f "$STATE_FILE" ]   && read -r st  < "$STATE_FILE"
    [ -f "$MESSAGE_FILE" ] && read -r msg < "$MESSAGE_FILE"

    emit "RUNNING=${running}
STATE=${st}
MESSAGE=${msg}"
}

# --- Load / Unload ---

cmd_load() {
    local name="$1"
    ensure_runtime

    local moddir
    moddir=$(find_kmod_by_name "$name")
    if [ -z "$moddir" ]; then
        emit "RESULT=not_found"; return 1
    fi

    if [ ! -f "${moddir}${name}.ko" ]; then
        log_error "$name: not built"
        emit "RESULT=not_built"; return 1
    fi

    if lsmod 2>/dev/null | grep -q "^${name} "; then
        emit "RESULT=already_loaded"; return 0
    fi

    log_info "Loading $name ..."
    if insmod "${moddir}${name}.ko" 2>>"$DKMS_LOG"; then
        log_info "$name: loaded"
        emit "RESULT=ok"
    else
        log_error "$name: insmod failed"
        emit "RESULT=error"; return 1
    fi
}

cmd_unload() {
    local name="$1"
    ensure_runtime

    if ! lsmod 2>/dev/null | grep -q "^${name} "; then
        emit "RESULT=not_loaded"; return 0
    fi

    log_info "Unloading $name ..."
    if rmmod "$name" 2>>"$DKMS_LOG"; then
        log_info "$name: unloaded"
        emit "RESULT=ok"
    else
        log_error "$name: rmmod failed (may be in use)"
        emit "RESULT=error"; return 1
    fi
}

# --- Autoload (marker file in kmod directory) ---
# disable file takes priority: if present, autoload is ignored

cmd_autoload() {
    local action="$1" name="$2"

    local moddir
    moddir=$(find_kmod_by_name "$name")
    if [ -z "$moddir" ]; then
        emit "RESULT=not_found"; return 1
    fi

    if [ -f "${moddir}disable" ]; then
        emit "RESULT=disabled"; return 1
    fi

    case "$action" in
        on)
            if [ -f "${moddir}autoload" ]; then
                emit "RESULT=already_on"
            else
                : > "${moddir}autoload"
                log_info "$name: autoload enabled"
                emit "RESULT=ok"
            fi
            ;;
        off)
            if [ -f "${moddir}autoload" ]; then
                rm -f "${moddir}autoload"
                log_info "$name: autoload disabled"
                emit "RESULT=ok"
            else
                emit "RESULT=already_off"
            fi
            ;;
        *) emit "RESULT=invalid" ;;
    esac
}

# --- Log ---

cmd_tail() {
    ensure_runtime
    tail -n "${1:-200}" "$DKMS_LOG" 2>/dev/null | tr '\n' '\t'
}

cmd_clear_log() {
    ensure_runtime
    if current_pid >/dev/null 2>&1; then
        emit "BUSY=1"; return 1
    fi
    : > "$DKMS_LOG"
    write_state "idle" "Idle"
    emit "CLEARED=1"
}

# --- Boot (called from service.sh) ---

cmd_boot() {
    ensure_runtime
    log_info "=== Boot autoload ==="

    for moddir in "$MAGISK_MODULES_DIR"/*/; do
        [ -d "$moddir" ] || continue
        [ -f "${moddir}disable" ] && continue
        [ -f "${moddir}autoload" ] || continue
        [ -f "${moddir}kmodinfo.cfg" ] || continue

        local name
        name=$(parse_cfg "${moddir}kmodinfo.cfg" "NAME")
        [ -z "$name" ] && continue

        if [ ! -f "${moddir}${name}.ko" ]; then
            log_info "Auto-building $name ..."
            do_build "$name" ""
        fi

        if [ -f "${moddir}${name}.ko" ]; then
            if ! lsmod 2>/dev/null | grep -q "^${name} "; then
                log_info "Auto-loading $name ..."
                if insmod "${moddir}${name}.ko" 2>>"$DKMS_LOG"; then
                    log_info "$name: loaded"
                else
                    log_error "$name: load failed"
                fi
            fi
        fi
    done

    log_info "=== Boot autoload complete ==="
}

# --- Main ---

case "$1" in
    list)        cmd_list ;;
    start)       cmd_start_task "$2" "$3" ;;
    do-task)     cmd_do_task "$2" "$3" ;;
    load)        cmd_load "$2" ;;
    unload)      cmd_unload "$2" ;;
    autoload)    cmd_autoload "$2" "$3" ;;
    task-status) cmd_task_status ;;
    tail)        cmd_tail "$2" ;;
    clear-log)   cmd_clear_log ;;
    boot)        cmd_boot ;;
    *)
        echo "Usage: $0 {list|start|load|unload|autoload|task-status|tail|clear-log|boot}" >&2
        exit 1
        ;;
esac
