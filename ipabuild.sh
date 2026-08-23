#!/bin/bash
# Compatibility wrapper — canonical build lives in scripts/build_ipa.sh
exec "$(dirname "$0")/scripts/build_ipa.sh" "$@"
