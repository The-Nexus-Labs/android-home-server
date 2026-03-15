PREPARE_ASSETS_STEP_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

step_id() {
  printf 'prepare-assets\n'
}

step_name() {
  printf 'Prepare pinned host assets\n'
}

step_state_key() {
  printf 'STATE_ASSETS_READY\n'
}

step_is_done() {
  assets_ready
}

step_guide() {
  cat <<'EOF'
This step runs entirely on the host computer.

It downloads and verifies:
  - platform-tools
  - the pinned GrapheneOS release and signature
  - Termux and Termux:Boot APKs
  - the Magisk APK and host patch helper

Manual action is not normally required.
EOF
}

step_apply() {
  local mode resolved_grapheneos_version platform_tools_zip grapheneos_zip grapheneos_sig allowed_signers
  local -a args=()

  require_cmd python3
  require_cmd unzip
  require_cmd ssh-keygen
  require_cmd sha256sum
  ensure_dirs

  mode=manifest
  if [[ "${1:-}" == '--download' ]]; then
    mode=download
  elif [[ "${1:-}" == '--manifest-only' || -z "${1:-}" ]]; then
    mode=manifest
  else
    die 'usage: prepare-assets [--manifest-only|--download]'
  fi

  args=(
    --device "$DEVICE_CODENAME"
    --grapheneos-version "$GRAPHENEOS_VERSION"
    --grapheneos-release-url-template "$GRAPHENEOS_RELEASE_URL_TEMPLATE"
    --grapheneos-release-sig-url-template "$GRAPHENEOS_RELEASE_SIG_URL_TEMPLATE"
    --grapheneos-allowed-signers-url "$GRAPHENEOS_ALLOWED_SIGNERS_URL"
    --platform-tools-version "$PLATFORM_TOOLS_VERSION"
    --platform-tools-url "$PLATFORM_TOOLS_URL"
    --platform-tools-sha256 "$PLATFORM_TOOLS_SHA256"
    --termux-apk-url "$TERMUX_APK_URL"
    --termux-boot-apk-url "$TERMUX_BOOT_APK_URL"
    --magisk-apk-url "$MAGISK_APK_URL"
    --magisk-host-patch-url "$MAGISK_HOST_PATCH_URL"
    --manifest "$MANIFEST_PATH"
    --download-dir "$DOWNLOAD_DIR"
  )

  if [[ "$mode" == 'download' ]]; then
    args+=(--download)
  fi

  python3 "$PREPARE_ASSETS_STEP_DIR/download_assets.py" "${args[@]}"
  log "Manifest ready at $MANIFEST_PATH"

  if [[ "$mode" == 'download' ]]; then
    resolved_grapheneos_version=$(manifest_value grapheneos.version)
    platform_tools_zip="$DOWNLOAD_DIR/$(manifest_value platform_tools.zip_name)"
    grapheneos_zip="$DOWNLOAD_DIR/$(manifest_value grapheneos.release_name)"
    grapheneos_sig="$DOWNLOAD_DIR/$(manifest_value grapheneos.release_sig_name)"
    allowed_signers="$DOWNLOAD_DIR/$(manifest_value grapheneos.allowed_signers_name)"

    log 'Verifying platform-tools archive checksum'
    echo "$(manifest_value platform_tools.sha256)  $platform_tools_zip" | sha256sum -c >/dev/null

    log 'Extracting platform-tools'
    rm -rf "$PLATFORM_TOOLS_DIR"
    unzip -oq "$platform_tools_zip" -d "$GRAPHENEOS_ROOT"

    log 'Verifying GrapheneOS release signature'
    ssh-keygen -Y verify -f "$allowed_signers" -I contact@grapheneos.org -n 'factory images' -s "$grapheneos_sig" < "$grapheneos_zip" >/dev/null

    log 'Extracting GrapheneOS release'
    rm -rf "$GRAPHENEOS_RELEASE_DIR/$DEVICE_CODENAME-install-$resolved_grapheneos_version"
    unzip -oq "$grapheneos_zip" -d "$GRAPHENEOS_RELEASE_DIR"

    log "Assets downloaded to $DOWNLOAD_DIR"
    log "Platform-tools extracted to $PLATFORM_TOOLS_DIR"
    log "GrapheneOS release extracted under $GRAPHENEOS_RELEASE_DIR"
  fi
}
