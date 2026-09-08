# latch

Keep a MacBook fully awake with the lid closed.

Close the laptop, put it in your bag, and your SSH sessions, builds, downloads
and agent tasks keep running exactly as if the lid were open — while the screen
stays dark and a watchdog makes sure you never come back to a machine that died
at 0%.

```
$ latch

latch  arming

  lid-close sleep    disabled
  idle assertion     held (caffeinate pid 48213)
  battery watchdog   armed (restores sleep below 20%)

  Safe to close the lid. Run latch off when you are done.
```

## Why not just `caffeinate`?

Because `caffeinate` does not survive a lid close.

`caffeinate` holds an assertion against *idle* sleep. Closing the lid is a
different signal entirely — macOS sleeps regardless, unless the machine is in
clamshell mode with an external display attached.

The setting that actually defeats lid-close sleep is `pmset disablesleep`, and
`latch` wraps it with the safety rails it badly needs.

## Install

Requires macOS. Works on both Apple Silicon and Intel.

```sh
git clone https://github.com/ashcbrd/latch.git
cd latch
./install.sh
```

The installer:

1. Symlinks `latch` into `/usr/local/bin`
2. Installs a **validated, tightly scoped** sudoers rule so `latch` runs
   without a password prompt

Run `./install.sh --no-sudoers` to skip step 2 and be prompted for your
password each time instead.

Because the binary is a symlink back into the clone, `git pull` updates your
installed copy.

## Usage

| Command | What it does |
| --- | --- |
| `latch` | Arm it. Safe to close the lid. |
| `latch --cool` | Arm it, plus Low Power Mode for cooler/longer running. |
| `latch --no-blank` | Arm it but leave the display on. |
| `latch off` | Restore normal sleep behaviour. |
| `latch status` | Show what is currently active. |
| `latch log` | Tail the activity log. |

Typical run:

```sh
latch          # screen blanks after 3s
                 # close the lid, put it in your bag
                 # ...work from your phone over SSH...
latch off      # when you're back
```

## How it works

| Layer | Purpose |
| --- | --- |
| `pmset -a disablesleep 1` | The only thing that defeats **lid-close** sleep |
| `caffeinate -dimsu` | Second layer against idle/disk sleep while open |
| `pmset displaysleepnow` | Blanks the display immediately — no wasted power |
| Watchdog process | Restores normal sleep below the battery floor |

The watchdog polls every 60 seconds. If you are on battery and drop to 20% or
below, it restores normal sleep and posts a macOS notification, so the machine
sleeps cleanly instead of hard-crashing at empty.

Tune with environment variables:

```sh
LATCH_BATTERY_FLOOR=30 latch     # restore sleep below 30%
LATCH_POLL_INTERVAL=30 latch     # poll twice as often
```

## Things worth knowing

**`disablesleep` is persistent and survives a reboot.** This is the single most
important thing to understand. If something kills `latch` uncleanly, the
setting stays on and your Mac will never sleep. `latch status` warns loudly
about exactly this state:

```
  Warning: sleep is disabled but latch is not armed.
  Run latch off to restore normal behaviour.
```

`latch off` and `./uninstall.sh` both clear it unconditionally.

**Teardown restores your machine's captured baseline**, not an assumed default.
Settings are read before anything is changed, so if you already ran Low Power
Mode, you still will afterwards.

**Heat is real but manageable.** Being awake is not what makes a laptop hot —
sustained CPU load is. A closed lid restricts airflow, so:

- Idle, SSH sessions, downloads, light agent work: fine, runs warm at most.
- An hour of full-core compilation in a zipped padded bag: it will get hot and
  macOS will thermally throttle.

Use `--cool` for the second case. It trades some CPU speed for meaningfully
lower thermals and longer battery.

## Security note

The sudoers rule grants passwordless sudo for **four exact commands only**:

```
pmset -a disablesleep 1
pmset -a disablesleep 0
pmset -a lowpowermode 1
pmset -a lowpowermode 0
```

No wildcards. A blanket `pmset *` rule would be a much wider grant, and this
deliberately is not that. The file is validated with `visudo -c` before it is
installed, because a malformed sudoers file can lock you out of `sudo`
entirely.

The honest tradeoff: any process running as your user can now toggle these
power settings without a password. That is a low-value target — it cannot
escalate to anything else — but it is a real widening of your sudo surface. Use
`./install.sh --no-sudoers` if you would rather type your password.

## Uninstall

```sh
./uninstall.sh
```

Restores normal sleep, removes the symlink, the sudoers rule and the state
directory. Leaves the cloned repo alone.

## License

MIT
