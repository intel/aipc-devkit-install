#!/bin/bash

################################################################################
# Intel Driver Static Installer Builder
#
# Purpose: Generates setup-static-drivers.sh, which installs:
#          - Intel GPU compute + media drivers from the Intel Graphics PPA
#            (ppa:kobuk-team/intel-graphics), per
#            https://dgpu-docs.intel.com/installation-guides/installing-packages-from-the-intel-ppa.html
#          - Intel NPU driver from the latest intel/linux-npu-driver GitHub release
#            (the PPA does not ship the NPU driver)
#
# Usage:
#   bash build-static-installer.sh                 # Verification mode (no files written)
#   bash build-static-installer.sh --build-static  # Generate setup-static-drivers.sh
#   bash build-static-installer.sh --help          # Show this help message
#
# Environment Variables:
#   GITHUB_TOKEN    Optional GitHub PAT for higher rate limits
#   http_proxy / https_proxy / no_proxy (or upper case)
#                   Honored for all downloads. If only http_proxy is set it is
#                   also used for HTTPS. Pass proxy settings to the generated
#                   installer at run time with sudo -E.
#
# Supported Ubuntu Versions:
#   - Ubuntu 24.04.X (noble)    GPU from PPA, NPU ubuntu2404 tarball
#   - Ubuntu 26.04.X (resolute) GPU from PPA, NPU ubuntu2604 tarball
#   - Others: not supported (the PPA only targets noble and resolute)
#
# Requirements:
#   - curl, jq (auto-installed with sudo apt if missing)
#   - apt package manager (Ubuntu)
#   - Internet connection
#
# Author: Intel Corporation
# License: Apache-2.0
################################################################################

set -e

show_help() {
    sed -n '2,/^################################################################################/p' "$0" | sed 's/^# //'
    exit 0
}

BUILD_STATIC=false
if [ "${1:-}" = "--build-static" ]; then
    BUILD_STATIC=true
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
elif [ -n "${1:-}" ]; then
    echo "ERROR: Unknown argument '$1'"
    echo "Use '--help' for usage information"
    exit 1
fi

PPA_NAME="ppa:kobuk-team/intel-graphics"
PPA_DOC_URL="https://dgpu-docs.intel.com/installation-guides/installing-packages-from-the-intel-ppa.html"
NPU_REPO="intel/linux-npu-driver"
OUTPUT_SCRIPT="setup-static-drivers.sh"

# Corporate proxies: curl/apt need https_proxy for HTTPS; reuse http_proxy when only that is set.
normalize_proxy_env() {
    local http="${http_proxy:-${HTTP_PROXY:-}}"
    local https="${https_proxy:-${HTTPS_PROXY:-$http}}"
    local no="${no_proxy:-${NO_PROXY:-}}"
    if [ -n "$http" ]; then export http_proxy="$http" HTTP_PROXY="$http"; fi
    if [ -n "$https" ]; then export https_proxy="$https" HTTPS_PROXY="$https"; fi
    if [ -n "$no" ]; then export no_proxy="$no" NO_PROXY="$no"; fi
}

normalize_proxy_env
if [ -n "${https_proxy:-}${http_proxy:-}" ]; then
    echo "Proxy configured for builder downloads (values not shown)"
fi

echo "=== Intel Driver Static Installer Builder on Linux ==="
echo "GPU drivers: Intel Graphics PPA ($PPA_NAME)"
echo "NPU driver:  latest $NPU_REPO GitHub release"
echo "No files will be downloaded or installed by this builder script"
echo

detect_and_validate_ubuntu_version() {
    echo "=== Detecting Ubuntu Version ==="
    if [ ! -f /etc/os-release ]; then
        echo "ERROR: Cannot find /etc/os-release"
        exit 1
    fi
    . /etc/os-release
    UBUNTU_VERSION="${VERSION_ID:-unknown}"
    UBUNTU_NAME="${PRETTY_NAME:-Unknown}"
    echo "Detected: $UBUNTU_NAME"

    if [ "${ID:-}" != "ubuntu" ]; then
        echo "ERROR: Ubuntu is required (detected ID='${ID:-unknown}')"
        exit 1
    fi

    case "$UBUNTU_VERSION" in
        24.04*)
            UBUNTU_CODENAME_TARGET="noble"
            NPU_TARBALL_SUFFIX="ubuntu2404"
            ;;
        26.04*)
            UBUNTU_CODENAME_TARGET="resolute"
            NPU_TARBALL_SUFFIX="ubuntu2604"
            ;;
        *)
            echo "ERROR: Ubuntu $UBUNTU_VERSION is not supported"
            echo "       The Intel Graphics PPA targets Ubuntu 24.04 (noble) and 26.04 (resolute)"
            exit 1
            ;;
    esac
    UBUNTU_MAJOR_MINOR=$(echo "$UBUNTU_VERSION" | cut -d. -f1,2)
    echo "✓ Ubuntu $UBUNTU_MAJOR_MINOR ($UBUNTU_CODENAME_TARGET) supported"
    echo "  NPU tarball flavor: $NPU_TARBALL_SUFFIX"
    echo
}

check_dependencies() {
    echo "=== Checking Required Dependencies ==="
    if ! command -v apt-get &> /dev/null; then
        echo "ERROR: 'apt-get' not found; this script requires Ubuntu"
        exit 1
    fi
    local missing=()
    for dep in curl jq; do
        if command -v "$dep" &> /dev/null; then
            echo "✓ $dep is installed"
        else
            echo "✗ $dep is not installed"
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Installing missing dependencies: ${missing[*]}"
        echo "Running: sudo -E apt-get update && sudo -E apt-get install -y ${missing[*]}"
        sudo -E apt-get update -qq
        sudo -E apt-get install -y "${missing[@]}"
        for dep in "${missing[@]}"; do
            command -v "$dep" &> /dev/null || { echo "ERROR: Failed to install $dep"; exit 1; }
        done
    fi
    echo
}

github_api() {
    local url="$1"
    local args=(-sS --max-time 20 --connect-timeout 10 -H "Accept: application/vnd.github+json")
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    fi
    curl "${args[@]}" "$url"
}

# Sets NPU_TAG, NPU_TARBALL_NAME, NPU_TARBALL_URL, NPU_TARBALL_SHA256
resolve_npu_release_api() {
    local response
    if ! response=$(github_api "https://api.github.com/repos/$NPU_REPO/releases/latest"); then
        echo "⚠ Network error contacting the GitHub API" >&2
        return 1
    fi
    if ! echo "$response" | jq -e . > /dev/null 2>&1; then
        echo "⚠ Invalid JSON from GitHub API" >&2
        return 1
    fi
    local message
    message=$(echo "$response" | jq -r '.message // empty')
    if [ -n "$message" ]; then
        echo "⚠ GitHub API: $message" >&2
        return 1
    fi

    NPU_TAG=$(echo "$response" | jq -r '.tag_name // empty')
    local pattern="^linux-npu-driver-.*-${NPU_TARBALL_SUFFIX}\\.tar\\.gz$"
    local asset
    asset=$(echo "$response" | jq -c --arg re "$pattern" '[.assets[]? | select(.name | test($re))] | first // empty')
    if [ -z "$NPU_TAG" ] || [ -z "$asset" ]; then
        echo "ERROR: No asset matching $pattern in $NPU_REPO ${NPU_TAG:-latest}" >&2
        echo "Available assets:" >&2
        echo "$response" | jq -r '.assets[]?.name' >&2
        return 1
    fi
    NPU_TARBALL_NAME=$(echo "$asset" | jq -r '.name')
    NPU_TARBALL_URL=$(echo "$asset" | jq -r '.browser_download_url')
    NPU_TARBALL_SHA256=$(echo "$asset" | jq -r '.digest // empty' | sed -n 's/^sha256://p')
    if [[ ! "$NPU_TARBALL_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
        echo "⚠ GitHub API has no valid SHA256 for $NPU_TARBALL_NAME" >&2
        return 1
    fi
}

# Fallback without the REST API (not rate limited): the /releases/latest redirect
# gives the tag and the expanded_assets page lists asset links and sha256 digests.
resolve_npu_release_html() {
    local base="https://github.com/$NPU_REPO/releases"
    NPU_TAG=$(curl -sSI --max-time 20 --connect-timeout 10 "$base/latest" \
        | tr -d '\r' | sed -n 's#^[Ll]ocation: .*/releases/tag/##p' | head -n 1)
    if [ -z "$NPU_TAG" ]; then
        echo "⚠ Could not resolve the latest tag from $base/latest" >&2
        return 1
    fi
    local html
    html=$(curl -sSL --max-time 30 --connect-timeout 10 "$base/expanded_assets/$NPU_TAG") || return 1
    local path
    path=$(echo "$html" | grep -oE "/$NPU_REPO/releases/download/$NPU_TAG/linux-npu-driver-[^\"/]*-${NPU_TARBALL_SUFFIX}\.tar\.gz" | head -n 1)
    if [ -z "$path" ]; then
        echo "⚠ No linux-npu-driver-*-${NPU_TARBALL_SUFFIX}.tar.gz asset on $base/tag/$NPU_TAG" >&2
        return 1
    fi
    NPU_TARBALL_NAME="${path##*/}"
    NPU_TARBALL_URL="https://github.com$path"
    NPU_TARBALL_SHA256=$(echo "$html" \
        | grep -oE "sha256:[0-9a-f]{64}\" aria-label=\"Copy to clipboard digest for ${NPU_TARBALL_NAME//./\\.}\"" \
        | head -n 1 | sed -E 's/^sha256:([0-9a-f]{64}).*/\1/')
    if [[ ! "$NPU_TARBALL_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
        echo "ERROR: No valid SHA256 for $NPU_TARBALL_NAME on $base/tag/$NPU_TAG" >&2
        return 1
    fi
}

resolve_npu_release() {
    echo "=== Resolving latest $NPU_REPO release ==="
    NPU_TAG=""; NPU_TARBALL_NAME=""; NPU_TARBALL_URL=""; NPU_TARBALL_SHA256=""
    if resolve_npu_release_api; then
        echo "Source: GitHub REST API"
    else
        echo "Falling back to the GitHub release page (no API rate limit)..."
        if ! resolve_npu_release_html; then
            echo "ERROR: Could not resolve the NPU driver release." >&2
            echo "       Check network/proxy settings, or set GITHUB_TOKEN (https://github.com/settings/tokens)." >&2
            return 1
        fi
        echo "Source: GitHub release page"
    fi

    echo "✓ NPU driver release: $NPU_TAG"
    echo "  Asset:  $NPU_TARBALL_NAME"
    echo "  URL:    $NPU_TARBALL_URL"
    echo "  SHA256: $NPU_TARBALL_SHA256"
    echo
}

check_ppa_reachable() {
    echo "=== Checking Intel Graphics PPA ==="
    local url="https://ppa.launchpadcontent.net/kobuk-team/intel-graphics/ubuntu/dists/$UBUNTU_CODENAME_TARGET/Release"
    if curl -sSfI --max-time 20 "$url" > /dev/null 2>&1; then
        echo "✓ PPA publishes $UBUNTU_CODENAME_TARGET: $url"
    else
        echo "⚠ Could not reach $url"
        echo "  The generated script needs HTTPS access to ppa.launchpadcontent.net and api.launchpad.net"
        echo "  Behind a corporate proxy, export http_proxy/https_proxy before running this builder"
    fi
    echo
}

generate_static_setup_script() {
    local tmp
    tmp=$(mktemp "${OUTPUT_SCRIPT}.XXXXXX")
    {
        cat << EOF
#!/bin/bash
################################################################################
# Intel GPU (PPA) + NPU driver installer
# Generated by build-static-installer.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
#
# Target:      Ubuntu $UBUNTU_MAJOR_MINOR ($UBUNTU_CODENAME_TARGET)
# GPU drivers: $PPA_NAME
#              $PPA_DOC_URL
# NPU driver:  $NPU_REPO $NPU_TAG ($NPU_TARBALL_NAME)
#
# Usage: sudo -E ./setup-static-drivers.sh   (-E keeps proxy settings)
################################################################################

TARGET_UBUNTU_VERSION="$UBUNTU_MAJOR_MINOR"
TARGET_CODENAME="$UBUNTU_CODENAME_TARGET"
PPA_NAME="$PPA_NAME"
NPU_TAG="$NPU_TAG"
NPU_TARBALL_NAME="$NPU_TARBALL_NAME"
NPU_TARBALL_URL="$NPU_TARBALL_URL"
NPU_TARBALL_SHA256="$NPU_TARBALL_SHA256"
EOF
        cat << 'EOF'

set -e
export DEBIAN_FRONTEND=noninteractive

GPU_COMPUTE_PACKAGES=(libze-intel-gpu1 libze1 intel-metrics-discovery intel-opencl-icd clinfo intel-gsc)
GPU_MEDIA_PACKAGES=(intel-media-va-driver-non-free libmfx-gen1.2 libvpl2 libvpl-tools libva-glx2 va-driver-all vainfo)
GPU_DEV_PACKAGES=(libze-dev intel-ocloc)
NPU_PACKAGES=(intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu intel-level-zero-npu-dbgsym)
# Packages earlier versions of this installer took from GitHub releases; reinstall from the PPA if present.
LEGACY_GITHUB_GPU_PACKAGES=(libze-intel-gpu1 intel-opencl-icd intel-ocloc libigdgmm12 intel-igc-core-2 intel-igc-opencl-2)
LEGACY_LEVEL_ZERO_PACKAGES=(level-zero level-zero-devel intel-level-zero-gpu)
LEGACY_APT_SOURCE=/etc/apt/sources.list.d/intel-gpu-noble.list
LEGACY_APT_KEY=/usr/share/keyrings/intel-graphics.gpg

configure_proxy() {
    local http="${http_proxy:-${HTTP_PROXY:-}}"
    local https="${https_proxy:-${HTTPS_PROXY:-$http}}"
    local no="${no_proxy:-${NO_PROXY:-}}"
    if [ -n "$http" ]; then export http_proxy="$http" HTTP_PROXY="$http"; fi
    if [ -n "$https" ]; then export https_proxy="$https" HTTPS_PROXY="$https"; fi
    if [ -n "$no" ]; then export no_proxy="$no" NO_PROXY="$no"; fi
    if [ -n "$http$https" ]; then
        echo "Proxy configured for installer downloads (values not shown)"
    fi
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

require_root_and_os() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: Run with sudo: sudo -E ./setup-static-drivers.sh"
        exit 1
    fi
    . /etc/os-release
    if [ "$(echo "${VERSION_ID:-}" | cut -d. -f1,2)" != "$TARGET_UBUNTU_VERSION" ]; then
        echo "ERROR: This script was generated for Ubuntu $TARGET_UBUNTU_VERSION but this system is ${PRETTY_NAME:-unknown}"
        echo "       Regenerate it with: bash build-static-installer.sh --build-static"
        exit 1
    fi
    NATIVE_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
    echo "Ubuntu: ${PRETTY_NAME}  Kernel: $(uname -r)  User: ${NATIVE_USER:-<unknown>}"
}

check_kernel() {
    if [ "$TARGET_UBUNTU_VERSION" = "24.04" ] && ! is_installed linux-generic-hwe-24.04; then
        echo "⚠ The HWE kernel (linux-generic-hwe-24.04) is not installed."
        echo "  Intel documents it as required on 24.04 for Lunar Lake, Battlemage and Panther Lake."
        echo "  This script does not change kernels. To switch, run:"
        echo "    sudo apt-get install -y --install-recommends linux-generic-hwe-24.04 && sudo reboot"
    fi
}

remove_legacy_conflicts() {
    echo "=== Removing conflicting packages and sources from earlier installs ==="
    if [ -e "$LEGACY_APT_SOURCE" ]; then
        echo "Removing legacy repositories.intel.com source: $LEGACY_APT_SOURCE"
        rm -f "$LEGACY_APT_SOURCE"
        rm -f "$LEGACY_APT_KEY"
    fi
    local purge=()
    for pkg in "${LEGACY_LEVEL_ZERO_PACKAGES[@]}"; do
        is_installed "$pkg" && purge+=("$pkg")
    done
    if [ ${#purge[@]} -gt 0 ]; then
        echo "Purging packages that conflict with the PPA libze1: ${purge[*]}"
        dpkg --purge --force-remove-reinstreq "${purge[@]}" || true
    fi
}

install_gpu_from_ppa() {
    echo "=== Installing Intel GPU drivers from $PPA_NAME ==="
    apt-get update
    apt-get install -y software-properties-common
    add-apt-repository -y "$PPA_NAME"
    apt-get update

    apt-get install -y "${GPU_COMPUTE_PACKAGES[@]}"
    apt-get install -y "${GPU_MEDIA_PACKAGES[@]}"
    apt-get install -y "${GPU_DEV_PACKAGES[@]}"

    # Locally installed .debs (from GitHub releases) can shadow PPA versions; pin them back to the PPA.
    local realign=()
    for pkg in "${LEGACY_GITHUB_GPU_PACKAGES[@]}"; do
        if is_installed "$pkg" && apt list --installed "$pkg" 2>/dev/null | grep -q "local\]"; then
            local ver
            ver=$(apt-cache madison "$pkg" | awk -F'|' '/kobuk-team/ {gsub(/ /,"",$2); print $2; exit}')
            [ -n "$ver" ] && realign+=("$pkg=$ver")
        fi
    done
    if [ ${#realign[@]} -gt 0 ]; then
        echo "Re-aligning GitHub-installed packages to PPA versions: ${realign[*]}"
        apt-get install -y --allow-downgrades "${realign[@]}"
    fi
}

install_npu_driver() (
    echo "=== Installing Intel NPU driver $NPU_TAG ==="
    if [[ ! "$NPU_TARBALL_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
        echo "ERROR: Missing or invalid SHA256 for $NPU_TARBALL_NAME"
        exit 1
    fi

    local work
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    echo "Downloading $NPU_TARBALL_URL"
    curl -fL --retry 3 -o "$work/$NPU_TARBALL_NAME" "$NPU_TARBALL_URL"
    echo "$NPU_TARBALL_SHA256  $work/$NPU_TARBALL_NAME" | sha256sum -c -
    tar -xf "$work/$NPU_TARBALL_NAME" -C "$work"
    shopt -s nullglob globstar
    local debs=("$work"/**/*.deb)
    if [ ${#debs[@]} -eq 0 ]; then
        echo "ERROR: No .deb files found in $NPU_TARBALL_NAME"
        exit 1
    fi

    apt-get install -y libtbb12
    local purge=()
    for pkg in "${NPU_PACKAGES[@]}"; do
        is_installed "$pkg" && purge+=("$pkg")
    done
    if [ ${#purge[@]} -gt 0 ]; then
        echo "Removing existing NPU packages: ${purge[*]}"
        dpkg --purge --force-remove-reinstreq "${purge[@]}" || true
    fi
    apt-get install -y "${debs[@]}"

    echo 'SUBSYSTEM=="accel", KERNEL=="accel*", GROUP="render", MODE="0660"' > /etc/udev/rules.d/10-intel-vpu.rules
    udevadm control --reload-rules || true
    udevadm trigger --subsystem-match=accel || true
)

configure_groups() {
    if [ -z "$NATIVE_USER" ] || [ "$NATIVE_USER" = "root" ]; then
        echo "⚠ Could not determine the non-root user; add it manually: sudo usermod -aG video,render <user>"
        return
    fi
    echo "Adding $NATIVE_USER to the video and render groups"
    usermod -aG video,render "$NATIVE_USER"
}

show_summary() {
    echo
    echo "=== Installation Summary ==="
    dpkg-query -W -f='${Package}\t${Version}\n' \
        libze-intel-gpu1 libze1 intel-opencl-icd intel-media-va-driver-non-free intel-ocloc \
        intel-driver-compiler-npu intel-fw-npu intel-level-zero-npu 2>/dev/null || true
    echo
    if command -v clinfo > /dev/null; then
        clinfo -l 2>/dev/null || true
    fi
    ls -l /dev/dri/render* /dev/accel/accel* 2>/dev/null || true
    echo
    echo "PPA source: $(ls /etc/apt/sources.list.d/ | grep -i kobuk-team || echo '<missing>')"
    echo
    echo "✅ Driver installation finished. Reboot to load the new drivers and group membership:"
    echo "   sudo reboot"
    echo "To uninstall the PPA later: sudo add-apt-repository --remove -y $PPA_NAME"
}

main() {
    echo "=== Intel GPU (PPA) + NPU driver installer ==="
    require_root_and_os
    configure_proxy
    check_kernel
    remove_legacy_conflicts
    install_gpu_from_ppa
    install_npu_driver
    configure_groups
    show_summary
}

main "$@"
EOF
    } > "$tmp"
    chmod +x "$tmp"
    bash -n "$tmp"
    mv "$tmp" "$OUTPUT_SCRIPT"
}

detect_and_validate_ubuntu_version
check_dependencies

if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "✓ GITHUB_TOKEN is configured (authenticated GitHub API requests)"
else
    echo "⚠ No GITHUB_TOKEN set (unauthenticated GitHub API; may hit rate limits)"
fi
echo

check_ppa_reachable

if ! resolve_npu_release; then
    echo "❌ Could not resolve the NPU driver release"
    exit 1
fi

if [ "$BUILD_STATIC" = "true" ]; then
    echo "=== Generating $OUTPUT_SCRIPT ==="
    generate_static_setup_script
    echo "✅ Generated $OUTPUT_SCRIPT"
    echo
    echo "📋 Summary:"
    echo "  - Ubuntu target:  $UBUNTU_MAJOR_MINOR ($UBUNTU_CODENAME_TARGET)"
    echo "  - GPU source:     $PPA_NAME"
    echo "  - NPU driver:     $NPU_TAG ($NPU_TARBALL_NAME)"
    echo
    echo -e "🚀 Run: \033[1;32msudo -E ./$OUTPUT_SCRIPT\033[0m  (-E keeps proxy settings)"
else
    echo "=== Verification complete (no files written) ==="
    if [ -f "$OUTPUT_SCRIPT" ]; then
        echo "✓ $OUTPUT_SCRIPT exists; regenerate with: bash build-static-installer.sh --build-static"
    else
        echo "Next steps:"
        echo "  1. bash build-static-installer.sh --build-static"
        echo "  2. sudo -E ./$OUTPUT_SCRIPT"
    fi
fi
