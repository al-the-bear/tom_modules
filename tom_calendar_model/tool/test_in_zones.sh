#!/bin/bash
# Runs this package's suite once per time zone, from UTC-11 to UTC+14.
#
# A day is read in a frame — the device's, the zone an appointment was made
# in — so a test that holds in one zone can fail in another. A machine has one
# zone; this gives the suite the others. Exit 1 when any zone fails.
#
#   tool/test_in_zones.sh                     # the standing set
#   tool/test_in_zones.sh Pacific/Honolulu    # the zones named
cd "$(dirname "$0")/.." || exit 2
zones=("$@")
if [ ${#zones[@]} -eq 0 ]; then
  zones=(Pacific/Pago_Pago Pacific/Honolulu America/New_York UTC
         Europe/Berlin Asia/Kolkata Asia/Tokyo Pacific/Kiritimati)
fi
failed=0
for zone in "${zones[@]}"; do
  output=$(TZ="$zone" dart test 2>&1)
  status=$?
  echo "$zone: $(printf '%s' "$output" | tr '\r' '\n' | grep -v '^$' | tail -1)"
  if [ $status -ne 0 ]; then
    failed=1
    printf '%s\n' "$output" | grep '\[E\]$' | sed 's/^.*test\//  /' | sort -u
  fi
done
exit $failed
