# latch

Keep a MacBook fully awake with the lid closed.

Close the laptop, put it in your bag, and your SSH sessions, builds, downloads
and agent tasks keep running exactly as if the lid were open, while the screen
stays dark and a watchdog makes sure you never come back to a machine that died
at 0%.

```
$ latch

latch  arming

  lid-close sleep    disabled
  idle assertion     held (caffeinate pid 48213)
  battery watchdog   armed (restores sleep at 20%)

  Safe to close the lid. Run latch off when you are done.
```

## Why not just `caffeinate`?

Because `caffeinate` does not survive a lid close.

`caffeinate` creates a power assertion, which holds off *idle* sleep. Closing
the lid is an explicit sleep request, and no assertion overrides it.

Apple's own closed-display mode does keep a Mac awake with the lid shut, but it
requires the power adapter, an external display, and an external keyboard or
mouse. That is a desk setup, not a bag.

The setting that defeats lid-close sleep on its own is `pmset disablesleep`, and
`latch` wraps it with the safety rails it needs.

## Install

Requires macOS. Works on Apple Silicon and Intel.

```sh
curl -fsSL https://raw.githubusercontent.com/ashcbrd/latch/main/install.sh | bash
```

That's it. No clone, no git, no GitHub account.

The installer:

1. Downloads `latch` and installs it to `/usr/local/bin`
2. Installs a **validated, tightly scoped** sudoers rule so `latch` never
   prompts for a password
3. Verifies the installed command actually runs

To skip the sudoers rule and be prompted for your password each time:

```sh
curl -fsSL https://raw.githubusercontent.com/ashcbrd/latch/main/install.sh | bash -s -- --no-sudoers
```

<details>
<summary>Installing from a clone instead</summary>

```sh
git clone https://github.com/ashcbrd/latch.git
cd latch
./install.sh
```

Installing from a clone symlinks the binary back into the checkout, so
`git pull` updates your installed copy.

</details>


## Usage

| Command | What it does |
| --- | --- |
| `latch` | Arm it. Safe to close the lid. |
| `latch --cool` | Arm it, plus Low Power Mode for cooler/longer running. |
| `latch --no-blank` | Arm it but leave the display on. |
| `latch off` | Restore normal sleep behaviour. |
| `latch status` | Show what is currently active. |
| `latch log` | Tail the activity log. |

Exit status: `latch status` returns 1 when sleep is disabled with no watchdog
running. `latch off` returns 1 if sleep could not be restored.

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
| `pmset displaysleepnow` | Blanks the display three seconds after arming |
| Watchdog process | Restores normal sleep at the battery floor |

`caffeinate` is run as `-ims` on purpose. The `-d` and `-u` flags keep the
display awake (and `-u` turns it back on), which is the opposite of the goal.

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

**Teardown records your Low Power Mode setting before changing it** and puts it
back afterwards, so if you already ran Low Power Mode, you still will. Sleep
itself is always re-enabled rather than restored, so the machine can never be
left awake by mistake.

**The watchdog needs the passwordless sudo rule.** It runs in the background
with no terminal, so it cannot type a password. Without the rule from
`install.sh` it can only send a notification when the battery runs low.
`latch status` shows `unattended sudo` so you can tell which situation you are
in.

**The watchdog does not survive a reboot.** `disablesleep` does. After a
restart, sleep stays disabled and nothing is watching the battery until you run
`latch` or `latch off`. `latch status` reports this as `ARMED (stale)` and exits
with status 1, so it is easy to check from a script or a shell prompt.

**latch refuses to arm below the floor.** If you are on battery at or under the
floor, arming would be undone at the first poll, so it says so up front instead.

**Heat is real but manageable.** Being awake is not what makes a laptop hot;
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
power settings without a password. That is a low-value target, since it cannot
escalate to anything else, but it is a real widening of your sudo surface. Use
`./install.sh --no-sudoers` if you would rather type your password.

## Uninstall

```sh
./uninstall.sh
```

Restores normal sleep, removes the symlink, the sudoers rule and the state
directory. Leaves the cloned repo alone.

## License

MIT
