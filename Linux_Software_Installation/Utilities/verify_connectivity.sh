#!/bin/bash
# Connectivity check for the Linux driver builder (build-static-installer.sh).
# GPU drivers come from the Intel Graphics PPA; the NPU driver from GitHub releases.
# Read-only: performs HTTPS requests only.

PPA_PATH="kobuk-team/intel-graphics/ubuntu"
NPU_REPO="intel/linux-npu-driver"
CURL_OPTS=(-fsSL --connect-timeout 10 --max-time 30)

if [ -n "${http_proxy:-}" ] && [ -z "${https_proxy:-}" ]; then
    export https_proxy="$http_proxy"
fi
echo "=== Driver Source Connectivity Test ==="
if [ -n "${http_proxy:-${HTTP_PROXY:-}${https_proxy:-${HTTPS_PROXY:-}}}" ]; then
    echo "Proxy configured (values not shown)"
else
    echo "No proxy configured"
fi
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN: set (value not shown)"
else
    echo "GITHUB_TOKEN: not set (optional; the builder falls back to the release page when rate limited)"
fi
echo

codename=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-noble}")
fail=0

echo "1. Intel Graphics PPA ($codename)..."
url="https://ppa.launchpadcontent.net/$PPA_PATH/dists/$codename/Release"
if curl "${CURL_OPTS[@]}" -o /dev/null "$url"; then
    echo "   ✓ $url"
else
    echo "   ✗ Cannot reach $url"
    echo "     Behind a proxy: export http_proxy/https_proxy (and use sudo -E)"
    fail=1
fi
if curl "${CURL_OPTS[@]}" -o /dev/null "https://api.launchpad.net/1.0/~kobuk-team/+archive/ubuntu/intel-graphics"; then
    echo "   ✓ api.launchpad.net reachable (used by add-apt-repository for the signing key)"
else
    echo "   ✗ Cannot reach api.launchpad.net (add-apt-repository needs it)"
    fail=1
fi

echo "2. GitHub ($NPU_REPO)..."
auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
api=$(curl -sSL --connect-timeout 10 --max-time 30 "${auth[@]}" "https://api.github.com/repos/$NPU_REPO/releases/latest" 2>/dev/null)
tag=$(echo "$api" | grep -m1 '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
if [ -n "$tag" ]; then
    echo "   ✓ GitHub API: latest release $tag"
else
    if echo "$api" | grep -qi "rate limit"; then
        echo "   ⚠ GitHub API rate limited; trying the release page"
    else
        echo "   ⚠ GitHub API not usable; trying the release page"
    fi
    loc=$(curl -sSI --connect-timeout 10 --max-time 30 "https://github.com/$NPU_REPO/releases/latest" | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}' | tail -n 1)
    tag="${loc##*/tag/}"
    if [ -n "$loc" ] && [ "$tag" != "$loc" ]; then
        echo "   ✓ Release page: latest release $tag"
    else
        echo "   ✗ Cannot reach github.com"
        fail=1
    fi
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "All driver sources reachable."
else
    echo "Some driver sources are unreachable; fix network/proxy settings before running the builder."
fi
exit "$fail"