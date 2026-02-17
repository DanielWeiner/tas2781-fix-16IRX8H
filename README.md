# tas2781-fix-16IRX8H
A script to fix the audio problems on Legion Pro 7 16IRX8H on Linux.
This is a combination of solutions from [this thread](https://forums.lenovo.com/t5/Ubuntu/Ubuntu-and-legion-pro-7-16IRX8H-audio-issues/m-p/5210709), with an automatic installer to eliminate manual steps.

## This repo is no longer maintained as the author does not have a laptop to test on. I hope this fix has been useful, and feel free to fork it and tinker if it's been less than useful.

## Features

- Apply a fix to the TAS2781 chip when pipewire is activated
- Apply the fix when awaking from suspend

Tested on Arch Linux, kernel 6.11, KDE Plasma 6.

## Installation

### Dependencies
[jq](https://jqlang.github.io/jq/) and [i2c-tools](https://archive.kernel.org/oldwiki/i2c.wiki.kernel.org/index.php/I2C_Tools.html) must be installed before applying the fix. Both are supported by mainstream package managers.

---

### Install

To install, simply run the following command:

```bash
curl -s https://raw.githubusercontent.com/DanielWeiner/tas2781-fix-16IRX8H/refs/heads/main/install.sh | bash -s --
```

Then make sure to **reboot your system.**

---

### Uninstall

To uninstall, run:

```bash
/usr/local/bin/tas2781-fix --uninstall
```

## Usage

### Re-trigger the fix

To re-trigger the fix, restart the service:

```bash
systemctl --user restart tas2781-fix.service
```
### Check the status of the fix

To check if the fix was applied, run:

```bash
systemctl status tas2781-fix.service
```

Note that this is the status of the system-level service, which actually executes the fix.

You should see something like this:

<pre>
<span style="color: #00ff00">●</span> tas2781-fix.service - Run the tas2781-fix script when triggered
     Loaded: loaded (/etc/systemd/system/tas2781-fix.service; static)
     Active: <span style="color: #00ff00">active (exited)</span> since Sat 2024-11-09 12:30:55 CST; 10min ago
 Invocation: a6d6b5bff24549c4a3fa6743420796a7
    Process: 9632 ExecStart=/usr/local/bin/tas2781-fix --execute (code=exited, status=0/SUCCESS)
   Main PID: 9632 (code=exited, status=0/SUCCESS)
   Mem peak: 3.6M
        CPU: 110ms
</pre>

This indicates that the fix ran and exited successfully.



---

### Disable the fix

To disable the fix, run:

```bash
systemctl --user disable tas2781-fix.service
```

This might be useful if you want to test that your audio works without the fix.

---

### Enable the fix after disabling

To enable the fix after disabling, run:

```bash
systemctl --user enable --now tas2781-fix.service
```
