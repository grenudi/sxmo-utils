# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Sxmo Contributors

# Shellspec formatting confuses shellcheck, so we have to disbale some checks
# SC2317: Command appears to be unreachable
# SC2329: Command not invoked
# SC2034: variable appears unused
# shellcheck disable=SC2317 disable=SC2329 disable=SC2034

# appended, so the mocks below come first (sxmo_suspend.sh is in scripts/core)
PATH="$PATH:$(pwd)/scripts/core"

# The loop never ends by itself: the sleep mock records each wait and fails
# after $SPEC_WAITS of them, which ends the script (it runs with set -e).

Describe "sxmo_autosuspend.sh"
	setup() {
		SPEC_TMP="$(mktemp -d)"
		XDG_STATE_HOME="$SPEC_TMP"
		export SPEC_TMP XDG_STATE_HOME
		unset SXMO_SUSPEND_RETRY_MAX
	}
	cleanup() {
		rm -rf "$SPEC_TMP"
	}
	BeforeEach setup
	AfterEach cleanup

	Mock cat
		if [ "$1" = /sys/power/wakeup_count ]; then
			echo 7
		else
			/bin/cat "$@"
		fi
	End

	Mock doas
		/bin/cat > /dev/null
	End

	Mock sxmo_hook_block_suspend.sh
		true
	End

	# Each call takes the next word of $SPEC_OUTCOMES (ok or fail), then fails
	Mock sxmo_suspend.sh
		echo x >> "$SPEC_TMP/suspends"
		n="$(wc -l < "$SPEC_TMP/suspends")"
		outcome="$(echo "$SPEC_OUTCOMES" | cut -d' ' -f"$n")"
		[ "$outcome" = ok ]
	End

	Mock sleep
		echo "$1" >> "$SPEC_TMP/waits"
		[ "$(wc -l < "$SPEC_TMP/waits")" -lt "$SPEC_WAITS" ]
	End

	waits() {
		tr '\n' ' ' < "$SPEC_TMP/waits"
	}

	It "waits twice as long after each failed suspend, up to 64s"
		export SPEC_OUTCOMES="" SPEC_WAITS=9
		When run script scripts/core/sxmo_autosuspend.sh
		The status should be failure
		The stderr should include "suspend failed, next try in 1s"
		The stderr should include "suspend failed, next try in 64s"
		The result of function waits should equal "1 2 4 8 16 32 64 64 64 "
	End

	It "caps the wait at SXMO_SUSPEND_RETRY_MAX"
		export SPEC_OUTCOMES="" SPEC_WAITS=5 SXMO_SUSPEND_RETRY_MAX=5
		When run script scripts/core/sxmo_autosuspend.sh
		The status should be failure
		The stderr should include "next try in 5s"
		The result of function waits should equal "1 2 4 5 5 "
	End

	It "starts over at 1s after a suspend that succeeds"
		export SPEC_OUTCOMES="fail fail ok fail" SPEC_WAITS=4
		When run script scripts/core/sxmo_autosuspend.sh
		The status should be failure
		The stderr should include "next try in 2s"
		The result of function waits should equal "1 2 10 1 "
	End
End
