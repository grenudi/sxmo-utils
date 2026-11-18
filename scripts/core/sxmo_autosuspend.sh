#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright 2022 Sxmo Contributors

# include common definitions
# shellcheck source=scripts/core/sxmo_common.sh
. sxmo_common.sh

set -e

# After a failed suspend, wait before the next try: 1s, then twice as long after
# each failure in a row, up to SXMO_SUSPEND_RETRY_MAX seconds (default 64). A
# kernel that keeps refusing to suspend is not asked again every second, and the
# devices it resumes on every aborted try (a USB link, a modem) are not cycled
# every second either. A suspend that succeeds starts over at 1s.
retry_max="${SXMO_SUSPEND_RETRY_MAX:-64}"
retry_delay=1
failed_suspend() {
	sxmo_log "suspend failed, next try in ${retry_delay}s"
	sleep "$retry_delay"
	retry_delay="$((retry_delay * 2))"
	if [ "$retry_delay" -gt "$retry_max" ]; then
		retry_delay="$retry_max"
	fi
}

last_check=0
wait_can_suspend() {
	# If we already checked recently, then there's nothing to do. This helps
	# mitigate the chance that running all checks could take too long and
	# cause suspend to fail.
	if [ "$((last_check + 10))" -gt "$(date +%s)" ]; then
		return
	fi

	sxmo_hook_block_suspend.sh

	last_check="$(date +%s)"
}

while true; do
	# Reading from wakeup_count blocks until there are no wakelocks
	wakeup_count=$(cat /sys/power/wakeup_count)

	wait_can_suspend

	# If the wakeup count has changed since we read it, this will fail so we
	# know to try again. If something takes a wake_lock after we do this, it
	# will cause the kernel to abort suspend.
	if ! echo "$wakeup_count" | doas tee /sys/power/wakeup_count > /dev/null; then
		continue
	fi

	# If sxmo_suspend failed then we didn't enter suspend, it is safe to
	# retry. The delay grows while it keeps failing, so we don't eat up the
	# system's resources (or bounce its devices) if the kernel can't suspend.
	if ! sxmo_suspend.sh; then
		failed_suspend
		continue
	fi
	retry_delay=1

	sleep 10
done
